

#  Define args sent to each ExtUtils:: method as standard
#
EXTUTILS_ARGV= "$(NAME)" "$(NAME_SYM)" "$(DISTNAME)" "$(DISTVNAME)" "$(VERSION)" "$(VERSION_SYM)" "$(VERSION_FROM)"


#  Name of ExtUtil::CVS Perl module
#
EXTUTILS_CVS=  ExtUtils::CVS


#  Check in files to CVS if needed, assuming MANIFEST checks out and files are not already
#  uptodate (as determined by ci_status test)
#
ci :: ci_manicheck
	@$(CVS) status $(DEV_NULL)
	@$(PERL) -M$(EXTUTILS_CVS) \
	-e "$(EXTUTILS_CVS)->ci_status(@ARGV)" -- $(EXTUTILS_ARGV) 				|| (	\
		$(CVS) commit 									&&	\
		$(CVS) commit -m "$(DISTNAME) version increment" -f "$(VERSION_FROM)" 	        && 	\
		$(CVS2CL) $(CVS2CL_ARG) 							&&	\
		$(CVS) commit -m "" $(CHANGELOG)                                                &&      \
        	$(PERL) -M$(EXTUTILS_CVS) 								\
			-e  "$(EXTUTILS_CVS)->ci_tag(@ARGV)"   						\
			--  $(EXTUTILS_ARGV)   							&&	\
		-$(MAKE) Makefile                                                                       \
		$(MAKE) ci_version_dump                                                                 \
	)

#		$(PERL) -M$(EXTUTILS_CVS) 								\
#			-e "$(EXTUTILS_CVS)->ci_version_dump(@ARGV)"					\
#			-- $(EXTUTILS_ARGV)							&& 	\


#  Make clean distribution and import into CVS
#
import :: disttest
	cd $(DISTVNAME) && $(MAKE) realclean
	cd $(DISTVNAME) && \
		$(CVS) -d $(CVSROOT) import -m "Initial import" \
		$(DISTNAME) $(DISTNAME)_IMPORT_1-0 $(DISTNAME)_1-1 
	rm -rf $(DISTVNAME)


#  Check manifest matches CVS
#
ci_manicheck ::
	@$(PERL) -M$(EXTUTILS_CVS) \
		-e "ExtUtils::CVS->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Check all files are in CVS and up to date
#
ci_status :: ci_manicheck
	@$(PERL) -M$(EXTUTILS_CVS) \
		-e "ExtUtils::CVS->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Print out current CVS version
#
ci_version ::
	@$(PERL) -M$(EXTUTILS_CVS) \
		-e "ExtUtils::CVS->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Dump current CVS version to Dumper.pm file, can be picked up later
#
ci_version_dump ::
	@$(PERL) -M$(EXTUTILS_CVS) \
		-e "ExtUtils::CVS->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Tag all files with current CVS version
#
ci_tag ::
	@$(PERL) -M$(EXTUTILS_CVS) \
		-e "ExtUtils::CVS->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


