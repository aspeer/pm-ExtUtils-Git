
ci :: ci_manicheck
	$(CVS) status $(DEV_NULL)
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_status('$(VERSION_FROM)')" || ( \
	$(CVS) commit && \
	$(CVS2CL) && \
	$(CVS) commit -m "" ChangeLog && \
	$(CVS) commit -m "" -f $(VERSION_FROM) && \
        $(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_tag( \
		'$(CVS)', '$(DISTNAME)', '$(VERSION_FROM)' )" && \
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_version_dump( \
		'$(NAME)', '$(VERSION_FROM)' )" && \
	$(PERL) \
		-e "$$::v=(do './$(VERSION_FROM)'); $$::_=$$::VERSION || $$::v; print qq($(NAME) Version: $$::_\n)" && \
	$(PERL) -MExtUtils::CVS=:all -MExtUtils::Dist=:all Makefile.PL \
	)

import :: disttest
	cd $(DISTVNAME) && $(MAKE) realclean
	cd $(DISTVNAME) && \
		$(CVS) -d $(CVSROOT) import -m "Initial import" \
		$(DISTNAME) $(DISTNAME)_IMPORT_1-0 $(DISTNAME)_1-1 
	rm -rf $(DISTVNAME)


ci_manicheck ::
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_manicheck('$(DISTNAME)')"


ci_status :: ci_manicheck
	$(CVS) status $(DEV_NULL)
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_status('$(VERSION_FROM)')"


ci_version ::
	$(PERL) \
		-e "$$::v=(do './$(VERSION_FROM)'); $$::_=$$::VERSION || $$::v; print qq($(NAME) Version: $$::_\n)"

ci_version_dump ::
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_version_dump( \
		'$(NAME)', '$(VERSION_FROM)' )"

ci_tag ::
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_tag( \
	'$(CVS)', '$(DISTNAME)', '$(VERSION_FROM)')"

branch ::
	$(CVS) tag -b $(DISTNAME)_`$(PERL) -e "do './$(VERSION_FROM)'; ($$::_=$$::VERSION)=~s/\\\./-/g;print"`-0 && \
	$(CVS) update -r $(DISTNAME)_`$(PERL) \
		-e "$$::v=(do'./$(VERSION_FROM)'); ($$::_=$$::VERSION || $$::v)=~s/\\\./-/g; print"`-0
