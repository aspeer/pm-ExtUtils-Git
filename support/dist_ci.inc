
ci :: ci_manicheck
	@$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_status('$(VERSION_FROM)')" || ( \
	$(CVS) commit && \
	$(CVS2CL) && \
	$(CVS) commit -m "" ChangeLog && \
	$(CVS) commit -m "" -f $(VERSION_FROM) && \
	$(CVS) tag $(DISTNAME)_`$(PERL) \
		-e "$$::v=(do '$(VERSION_FROM)'); ($$::_=$$::VERSION || $$::v)=~s/\\\./-/g; print"` && \
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_dump_version( \
		'$(NAME)', '$(VERSION_FROM)' )" && \
	$(PERL) \
		-e "$$::v=(do '$(VERSION_FROM)'); $$::_=$$::VERSION || $$::v; print qq($(NAME) Version: $$::_\n)" && \
	$(PERL) Makefile.PL \
	)

import : disttest
	cd $(DISTVNAME) && $(MAKE) realclean
	cd $(DISTVNAME) && \
		$(CVS) -d $(CVSROOT) import -m "Initial import" \
		$(DISTNAME) $(DISTNAME)_IMPORT_1-0 $(DISTNAME)_1-1 
	rm -rf $(DISTVNAME)


ci_manicheck :
	@$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_manicheck('$(DISTNAME)')"


ci_status : ci_manicheck
	@$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_status('$(VERSION_FROM)')"


ci_dump_version :
	$(PERL) -MExtUtils::CVS -e "ExtUtils::CVS->ci_dump_version( \
		'$(NAME)', '$(VERSION_FROM)' )"

branch :
	$(CVS) tag -b $(DISTNAME)_`$(PERL) -e "do '$(VERSION_FROM)'; ($$::_=$$::VERSION)=~s/\\\./-/g;print"`-2 && \
	$(CVS) update -r $(DISTNAME)_`$(PERL) \
		-e "$$::v=(do'$(VERSION_FROM)'); ($$::_=$$::VERSION || $$::v)=~s/\\\./-/g; print"`-2	
