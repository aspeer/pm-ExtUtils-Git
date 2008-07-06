

#  Check in files to CVS if needed, assuming MANIFEST checks out and files are not already
#  uptodate (as determined by ci_status test)
#
ci :: ci_manicheck
	@$(CVS) status $(DEV_NULL)
	@$(PERL) -M$(EXTUTILS_CVS) \
	-e "$(EXTUTILS_CVS)->ci_status(@ARGV)" -- $(EXTUTILS_ARGV) 				|| (	\
		$(CVS) status $(DEV_NULL)							&&	\
		$(CVS) commit 									&&	\
		$(CVS) commit -m "$(DISTNAME) version increment" -f "$(VERSION_FROM)" 	        && 	\
		$(CVS2CL) $(CVS2CL_ARG) 							&&	\
		$(MAKE) Makefile_PL                                                             &&	\
		$(MAKE) metafile 								&&	\
		$(CVS) commit -m "" $(CHANGELOG) $(METAFILE)                                    &&      \
        	$(PERL) -M$(EXTUTILS_CVS) 								\
			-e  "$(EXTUTILS_CVS)->ci_tag(@ARGV)"   						\
			--  $(EXTUTILS_ARGV)   							&&	\
		$(PERL) -M$(EXTUTILS_CVS) 								\
			-e "$(EXTUTILS_CVS)->ci_version_dump(@ARGV)"					\
			-- $(EXTUTILS_ARGV)							        \
	)



#  Make clean distribution and import into CVS
#
git_import ::
	@$(GIT_EXE) init -q && \
	$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)

#  Check manifest matches CVS
#
git_manicheck ::
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Check all files are in CVS and up to date
#
git_status :: git_manicheck
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
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


#  Create links
#
links ::
	@$(PERL) -M$(EXTUTILS_CVS) \
		-e "ExtUtils::CVS->$@(@ARGV)" \
		-- $(NAME) $(TO_INST_PM)
