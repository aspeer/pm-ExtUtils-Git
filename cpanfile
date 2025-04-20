requires 'App::Markpod';
requires 'ExtUtils::MM_Any';
requires 'File::Grep';
requires 'File::Temp';
requires 'Git::Wrapper';
requires 'Module::Extract::VERSION';
requires 'PPI';
requires 'Software::License';
requires 'Software::LicenseUtils';
suggests 'Docbook::Convert';
suggests 'IPC::Run3';
suggests 'Markdown::Pod';
suggests 'Module::CPANTS::Analyse';
suggests 'Module::CPANTS::Kwalitee';
suggests 'Module::CPANTS::SiteKwalitee';
suggests 'Perl::MinimumVersion';
suggests 'XML::Twig';

on configure => sub {
    requires 'Tie::File';
    requires 'perl', '5.006';
};

on test => sub {
    requires 'Test::More';
};
