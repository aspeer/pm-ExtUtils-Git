#  This file is part of ExtUtils::Git.
#
#  This software is copyright (c) 2015 by Andrew Speer <andrew.speer@isolutions.com.au>.
#
#  This is free software; you can redistribute it and/or modify it under
#  the same terms as the Perl 5 programming language system itself.
#
#  Full license text is available at:
#
#  <http://dev.perl.org/licenses/>
#
This file is part of <: $OUT=$name :>.

<: $OUT=$notice :>
<: if ($url) {

$OUT=<<"LICENSE_URL";
Full license text is available at:

<$url>
LICENSE_URL

}

:>
