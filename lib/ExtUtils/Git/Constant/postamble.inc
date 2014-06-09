#  Generic targets that all run the same named method from the ExtUtils::Git module
#
GIT_TARGETS=git_manicheck git_version git_ignore git_tag git_autolicense git_version_increment  \
	git_lint git_version_dump git_version_increment_files git_autocopyright git_remote git_push

GIT_PERL_PM=$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV)

$(GIT_TARGETS) :
	@$(GIT_PERL_PM)


#  Targets that have dependencies, extra steps etc.
#
git_ci : git_manicheck git_autolicense git_autocopyright
	$(GIT_EXE) commit -a


git_merge : git_ci
	@$(GIT_PERL_PM) && \
	$(MAKE) git_version_increment


git_release : 
	$(MAKE) git_version_increment 
	$(GIT_EXE) commit -a -m "VERSION increment"
	@$(GIT_PERL_PM)
	$(MAKE) git_tag
	$(MAKE) git_dist



#  Build distribution
#
git_dist : git_status
#	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN)
	$(MAKE) tardist
#	$(MAKE) git_version_increment


#  Make new repository and import files into Git
#
git_import : git_init git_autolicense
	@$(GIT_PERL_PM) && \
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


git_arg :
	@echo $(EXTUTILS_ARGV)


#  Check all files are in git and up to date
#
git_status : git_manicheck
	@$(GIT_PERL_PM)



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
		do echo $$d; perltidy -se -b $$d; done
	@for d in $(EXE_FILES); do perltidy -x -b $$d; done


#  perlcritic of all files
#
perlcritic : all
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm$$/} @ARGV)' -- $(TO_INST_PM)`; \
		do echo $$d; perlcritic $$d; done
	@for d in $(EXE_FILES); do perlcritic $$d; done


#  Crete changelog
#
git_distchanges : create_distdir
	$(NOECHO) cd $(DISTVNAME) && \
	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN) && \
	$(ABSPERLRUN) -MExtUtils::Manifest=maniadd -e 'exit unless -e q{$(CHANGELOG_FN)};' \
		-e 'eval { maniadd({q{$(CHANGELOG_FN)} => q{Module ChangeLog (added by ExtUtils::Git)}}) }' \
		-e '    or print "Could not add $(CHANGELOG_FN) to MANIFEST: $$$${'\''@'\''}\n"' --
