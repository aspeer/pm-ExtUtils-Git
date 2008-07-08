

#  Check in files to Git if needed, assuming MANIFEST checks out and files are not already
#  uptodate (as determined by git_status test)
#
git_ci :: git_manicheck
	@$(PERL) -M$(EXTUTILS_GIT) \
	-e "$(EXTUTILS_GIT)->git_status(@ARGV)" -- $(EXTUTILS_ARGV) 				|| (	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_version_increment(@ARGV)"				\
			-- $(EXTUTILS_ARGV)							&&	\
		$(MAKE) metafile 								&&	\
		$(GIT_EXE) commit -a								&&	\
		$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN)				&&	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_tag(@ARGV)"						\
			-- $(EXTUTILS_ARGV)							&&	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_version_dump(@ARGV)"					\
			-- $(EXTUTILS_ARGV)								\
	)



#  Build distribution
#
git_dist :: git_ci
	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN)
	$(MAKE) tardist		


#  Make new repository and import files into Git
#
git_import ::
	$(GIT_EXE) init -q && \
	$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV) && \
	$(GIT_EXE) remote add origin $(GIT_REPO)/$(DISTNAME)


#  Check manifest matches git
#
git_manicheck ::
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Check all files are in git and up to date
#
git_status :: git_manicheck
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Increment version_from file
#
git_version_increment ::
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Print current version
#
git_version ::
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Tag current version
#
git_tag ::
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Dump current git version to Dumper.pm file, can be picked by packaging tool later
#
git_version_dump ::
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


