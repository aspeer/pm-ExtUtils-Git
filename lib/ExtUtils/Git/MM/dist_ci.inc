#  This file is part of ExtUtils::Git.
#  
#  This software is copyright (c) 2014 by Andrew Speer <andrew.speer@isolutions.com.au>.
#  
#  This is free software; you can redistribute it and/or modify it under
#  the same terms as the Perl 5 programming language system itself.
#  
#  Full license text is available at:
#  
#  <http://dev.perl.org/licenses/>
#  







#  Check in files to Git if needed, assuming MANIFEST checks out and files are not already
#  uptodate (as determined by git_status test)
#
git_ci0 : git_manicheck
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


git_ci1 : git_manicheck autolicense
	@$(PERL) -M$(EXTUTILS_GIT) \
	-e "$(EXTUTILS_GIT)->git_status(@ARGV)" -- $(EXTUTILS_ARGV) 				|| (	\
		$(PERL) -M$(EXTUTILS_GIT)								\
			-e "$(EXTUTILS_GIT)->git_commit(@ARGV)"						\
			-- $(EXTUTILS_ARGV)							&&	\
		$(GIT_EXE) push	origin								        \
	)

git_ci : git_manicheck git_autolicense
	$(GIT_EXE) commit -a


git_merge : git_ci
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


git_release : 
	$(MAKE) git_version_increment 
	$(GIT_EXE) commit -a -m "VERSION increment"
	@$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->git_make(@ARGV)" \
		-- $(EXTUTILS_ARGV)
	$(MAKE) git_tag
	$(MAKE) git_dist

#  Push
#
git_push :
	$(GIT_EXE) push origin
	$(GIT_EXE) push origin --tags


#  Build distribution
#
git_dist : git_status
#	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN)
	$(MAKE) tardist
#	$(MAKE) git_version_increment


#  Make new repository and import files into Git
#
git_import : git_init git_autolicense
	$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV) && \
	$(GIT_EXE) commit -m "MANIFEST Import"
#	$(GIT_EXE) push --mirror origin


#  Init local git repo
#
git_init :
	@if [ ! -d .git ]; then \
	    $(GIT_EXE) init || exit 1; \
	    $(GIT_EXE) remote add origin $(GIT_REPO)/$(DISTNAME); \
	    $(MAKE) git_ignore \
#	    $(PERL) -M$(EXTUTILS_GIT) \
#		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
#		-- $(EXTUTILS_ARGV); \
	fi


#  Commit
#
git_commit0 :
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
	@$(PERL) -Ilib -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Increment commit
#
git_version_increment_commit :
	@$(PERL) -Ilib -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)


#  Create .gitignore
#
git_ignore :
	@$(PERL) -Ilib -M$(EXTUTILS_GIT) \
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
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm$$/} @ARGV)' -- $(TO_INST_PM)`; \
		do PERL5INC=$(INST_LIB) $(PERL) -I$(INST_LIB) $(MAKEFILELIB) -c -w $$d; done
	@for d in $(EXE_FILES); do PERL5INC=$(INST_LIB) $(PERL) -I$(INST_LIB) $(MAKEFILELIB) -c -w $$d; done


#  perltidy of all files
#
perltidy : all
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm$$/} @ARGV)' -- $(TO_INST_PM)`; \
		do perltidy -se -b $$d; done
	@for d in $(EXE_FILES); do perltidy -x -b $$d; done


#  perlcritic of all files
#
perlcritic : all
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm$$/} @ARGV)' -- $(TO_INST_PM)`; \
		do perlcritic $$d; done
	@for d in $(EXE_FILES); do perlcritic $$d; done


#  generate license file
#
git_autolicense :
	@$(PERL) -Ilib -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(LICENSE) "$(AUTHOR)"


git_distchanges : create_distdir
	$(NOECHO) cd $(DISTVNAME) && \
	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN) && \
	$(ABSPERLRUN) -MExtUtils::Manifest=maniadd -e 'exit unless -e q{$(CHANGELOG_FN)};' \
		-e 'eval { maniadd({q{$(CHANGELOG_FN)} => q{Module ChangeLog (added by ExtUtils::Git)}}) }' \
		-e '    or print "Could not add $(CHANGELOG_FN) to MANIFEST: $$$${'\''@'\''}\n"' --
