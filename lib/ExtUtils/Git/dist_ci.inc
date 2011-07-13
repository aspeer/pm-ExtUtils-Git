

#  Check in files to Git if needed, assuming MANIFEST checks out and files are not already
#  uptodate (as determined by git_status test)
#
git_ci : git_manicheck
	@$(PERL) -M$(EXTUTILS_GIT) \
	-e "$(EXTUTILS_GIT)->git_status(@ARGV)" -- $(EXTUTILS_ARGV) 				|| (	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_version_increment(@ARGV)"				\
			-- $(EXTUTILS_ARGV)							&&	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_version_increment_files(@ARGV)"			\
			-- $(EXTUTILS_ARGV)							&&	\
		$(MAKE) -n 									||	\
		$(MAKE) -n metafile 								&&	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_commit(@ARGV)"						\
			-- $(EXTUTILS_ARGV)							&&	\
		$(GIT_EXE) log -M --name-status > $(CHANGELOG_FN)				&&	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_tag(@ARGV)"						\
			-- $(EXTUTILS_ARGV)							&&	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_version_dump(@ARGV)"					\
			-- $(EXTUTILS_ARGV)							&&	\
		$(GIT_EXE) push	--mirror origin								\
	)



#  Push
#
git_push :
	$(GIT_EXE) push --mirror origin


#  Build distribution
#
git_dist : git_ci
	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN)
	$(MAKE) tardist


#  Make new repository and import files into Git
#
git_import :
	$(MAKE) metafile
	$(MAKE) git_init && \
	$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV) && \
	$(GIT_EXE) commit -m "MANIFEST Import"
	$(GIT_EXE) push --mirror origin


#  Init local git repo
#
git_init :
	@if [ ! -d .git ]; then \
	    $(GIT_EXE) init -q || exit 1; \
	    $(GIT_EXE) remote add origin $(GIT_REPO)/$(DISTNAME); \
	fi


#  Commit
#
git_commit :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Check manifest matches git
#
git_manicheck :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Check all files are in git and up to date
#
git_status : git_manicheck
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Increment version_from file
#
git_version_increment :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Increment VERSION in any files that have changed
#
git_version_increment_files :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Print current version
#
git_version :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Tag current version
#
git_tag :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Lint the files for old RCS/CVS keywords
#
git_lint :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)

#  Dump current git version to Dumper.pm file, can be picked by packaging tool later
#
git_version_dump :
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  perl -c -w check of all files
#
cw : all
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm/} @ARGV)' -- $(TO_INST_PM)`; \
		do PERL5INC=$(INST_LIB) $(PERL) -I$(INST_LIB) $(MAKEFILELIB) -c -w $$d; done
	@for d in $(EXE_FILES); do PERL5INC=$(INST_LIB) $(PERL) -I$(INST_LIB) $(MAKEFILELIB) -c -w $$d; done
