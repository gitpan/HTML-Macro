# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..6\n"; }
END {print "not ok 1\n" unless $loaded;}
use HTML::Macro;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

$ifp = HTML::Macro->new();
$ifp->set ('@precompile', 1);
$result = $ifp->process ('test1.html');
if ($result eq '<if expr="0">ok</if>')
{
    print "ok 1a\n";
} else
{
    print "not ok 1a: $result\n";
}


$ifp = HTML::Macro->new();
$ifp->declare ('var', 'missing', 'outer');
$ifp->set ('var', 'value');
$ifp->set ('qvar', '"<quote me>"');
$ifp->set ('var_var', 'value2');
$ifp->set ('var_UP', 'value3');
$result = $ifp->process ('test.html');
if ($result eq 'value &quot;&lt;quote me&gt;&quot; value2 value_x ##VAR_UP##')
{
    print "ok 2\n";
} else
{
    print "not ok 2: $result\n";
}

$ifp = HTML::Macro->new();
$ifp->set ('val', 1);
$result = $ifp->process ('test2.html');
if ($result eq "greater\ngreaterequal\ngreaterequal\ngreater\ngreater\ngreaterequal\ngreaterequal\ngreater\nok\n")
{
    print "ok 3\n";
} else
{
    print "not ok 3: $result\n";
}

$ifp = HTML::Macro->new();
$ifp->set ('val', 1);
$ifp->set ('yes', 1);
$result = $ifp->process ('test3.html');
if ($result eq "greater\nlessequal\n")
{
    print "ok 4\n";
} else
{
    print "not ok 4: $result\n";
}

$ifp = HTML::Macro->new();
$ifp->set ('pagenum', 2);
$ifp->set ('val', 2);
$result = $ifp->process ('test4.html');
if ($result eq "2greater\ngreaterequal\ngreaterequal\ngreater\ngreater\ngreaterequal\ngreaterequal\ngreater\nok\n\ngreater\ngreaterequal\ngreaterequal\ngreater\ngreater\ngreaterequal\ngreaterequal\ngreater\nok\n")
{
    print "ok 5\n";
} else
{
    print "not ok 5: $result\n";
}

$ifp = HTML::Macro->new();
$ifp->set ('pagenum', 2);
$ifp->set ('val', 2);
$result = $ifp->process ('test5.html');
if ($result eq '<include/ file="/etc/passwd"><if expr="##YES##">greater</if><quote preserve="1">output should have the quote tag in it</quote>#VAL#')
{
    print "ok 6\n";
} else
{
    print "not ok 6: $result\n";
}

$ifp = HTML::Macro->new();
$ifp->push_incpath ('include');
$result = $ifp->process ('test6.html');
if ($result eq 'included file stuff.htmlincluded file substuff.html')
{
    print "ok 7\n";
} else
{
    print "not ok 7: $result\n";
}

$ifp->set ('@collapse_whitespace', 1);
$result = $ifp->process ('test7.html');
if ($result eq 'This has extra white space end ')
{
    print "ok 8\n";
} else
{
    print "not ok 8: $result\n";
}

$ifp->set ('@collapse_whitespace', 0);
$ifp->set ('@collapse_blank_lines', 1);
$result = $ifp->process ('test7.html');
if ($result eq "This       has        extra\n    white     space\nend\n")
{
    print "ok 9\n";
} else
{
    print "not ok 9: $result\nshould be:\nThis has extra\n    white     space\nend\n";
}

