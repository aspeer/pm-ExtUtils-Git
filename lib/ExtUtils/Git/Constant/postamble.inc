GIT_TARGETS=git_manicheck git_version git_ignore git_tag git_autolicense git_version_increment_commit \
	git_lint git_version_dump git_version_increment_files git_remote git_push git_arg git_version_reset \
	git_autocopyright_pm git_autocopyright_pod git_autocopyright_xml git_autocopyright_md \
	perlver markpod


#  Other targets that need the Makefile rebuilt after running
#
GIT_TARGETS_BRANCH=git_branch_master git_branch_development git_master git_development


#  Command to call ExtUtils::Git module with intended target as method
#
GIT_PERL_PM=$(PERL) -M$(EXTUTILS_GIT) \
		-e "$(EXTUTILS_GIT)->$@(@ARGV)" \
		-- $(EXTUTILS_ARGV) $(MAKECMDGOALS)

#  Targets that can run without rebuiling Makefile
#
$(GIT_TARGETS) :
	@$(GIT_PERL_PM)


#  Targets that need makefile rebuilt
$(GIT_TARGETS_BRANCH) : git_ci
	@$(GIT_PERL_PM)
	$(MAKE)


#  Targets that have dependencies, extra steps etc. 
#
git_ci : git_manicheck doc cpanfile
	$(GIT_EXE) commit -a


#  Git commit is an aliase for git_ci
#
git_commit : git_ci


#  Target to build a release
#
git_release :
	$(MAKE) git_version_increment 
	$(MAKE) git_dist


#  Version increment
#
git_version_increment : git_status git_autolicense git_autocopyright
	@$(GIT_PERL_PM)
	-$(MAKE)
	$(MAKE) git_version_increment_commit 
	$(MAKE) git_tag


#  Version increment force - no checks
#
git_version_increment_force : 
	@$(GIT_PERL_PM)


#  Build distribution
#
git_dist : git_status 
	$(MAKE) $(DIST_DEFAULT_TARGET)


#  Make new repository and import files into Git
#
git_import : git_init git_autolicense git_autocopyright cpanfile
	@$(GIT_PERL_PM) && \
	$(GIT_EXE) commit -m "MANIFEST Import"


#  Init local git repo
#
git_init :
	@if [ ! -d .git ]; then \
	    $(GIT_EXE) init || exit 1; \
	    $(MAKE) git_remote; \
	    $(MAKE) git_ignore; \
	fi


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
	@for d in $(EXE_FILES); do echo $$d; perltidy -x -b $$d; done


#  perlcritic of all files
#
perlcritic : all
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm$$/} @ARGV)' -- $(TO_INST_PM)`; \
		do echo $$d; perlcritic $$d; done
	@for d in $(EXE_FILES); do echo $$d; perlcritic $$d; done


#  subsort
#
subsort : all
	@for d in `$(PERL) -e 'print join q[ ], (grep {/\.pm$$/} @ARGV)' -- $(TO_INST_PM)`; \
		do echo $$d; perltidy_subsort $$d; done
	@for d in $(EXE_FILES); do echo $$d; perltidy_subsort $$d; done


#  kwalitee tests
#
kwalitee : all tardist
	@$(GIT_PERL_PM)


#  Crete changelog
#
git_distchanges : create_distdir
	$(NOECHO) cd $(DISTVNAME) && \
	$(GIT_EXE) rev-list  --all --pretty > $(CHANGELOG_FN) && \
	$(ABSPERLRUN) -MExtUtils::Manifest=maniadd -e 'exit unless -e q{$(CHANGELOG_FN)};' \
		-e 'eval { maniadd({q{$(CHANGELOG_FN)} => q{Module ChangeLog (added by ExtUtils::Git)}}) }' \
		-e '    or print "Could not add $(CHANGELOG_FN) to MANIFEST: $$$${'\''@'\''}\n"' --


#  Update copyrights
#
git_autocopyright : git_autocopyright_pm git_autocopyright_xml git_autocopyright_pod git_autocopyright_md


#  Create README
#
pandoc_readme :
	$(MAKE) git_autocopyright_xml
	[ -f "$(VERSION_FROM).xml" ] && pandoc -f docbook -t gfm "$(VERSION_FROM).xml" > README.md || $(TRUE)
	[ -f "$(VERSION_FROM).xml" ] && pandoc -f docbook -t plain $(VERSION_FROM).xml > README || $(TRUE)

markpod_readme :
	$(MAKE) git_autocopyright_md
	@$(GIT_PERL_PM)


#  Create doc
#
doc : git_autocopyright_pm pandoc_readme markpod markpod_readme
	@$(GIT_PERL_PM)


#  Make CPANM file, scan deps
#
cpanfile :
	scan-perl-prereqs-nqlite  --exclude_core --suggests --save_cpanfile 
	@$(GIT_PERL_PM)

scandeps :
	scan-perl-prereqs-nqlite  --exclude_core 

