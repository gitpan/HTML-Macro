# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}
use HTML::Macro;
use HTML::Macro::Loop;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

$ifp = HTML::Macro->new();
my $loop = $ifp->new_loop ('loop', 'value');
$loop->push_array (1);
$loop->push_array (2);
$result = $ifp->process ('test.html');
if ($result eq "1_name2_name\n1: <loop id=\"quoted\">#VALUE#</loop>\n2: <loop id=\"quoted\">#VALUE#</loop>\n")
{
    print "ok 2\n";
} else
{
    print "not ok 2: $result\n";
}

$ifp = HTML::Macro->new();
my $outer = $ifp->new_loop ('outer', 'i');
$outer->push_hash ({'i' => 1});
my $inner = $outer->new_loop ('inner', 'j');
$inner->push_array (1);
$inner->push_array (2);
$outer->push_hash ({'i' => 2});
$inner = $outer->new_loop ('inner', 'j');
$inner->push_array (1);
$inner->push_array (2);
$result = $ifp->process ('test2.html');
if ($result eq '(1,1)(1,2)(2,1)(2,2)')
{
    print "ok 3\n";
} else
{
    print "not ok 3: $result\n";
}

$ifp = HTML::Macro->new();
$ifp->set ('outer', 1);
my $testloop = $ifp->new_loop ('testloop', 'val');
$testloop->push_array ('x');
$result = $ifp->process ('test3.html');
if ($result eq '0x1') {
    print "ok 3a\n";
} else {
    print "not ok 3a: $result\nshould be 0x1\n";
}
$ifp = HTML::Macro->new();
$ifp->set ('quoteme', 1);
$testloop = $ifp->new_loop ('testloop', 'dummy');
$testloop->push_hash ({'dummy' => 1});
$result = $ifp->process ('test4.html');
if ($result eq "\n  <quote preserve=\"#QUOTEME#\">\n    <quote><if expr=\"0\">0</if></quote>\n  </quote>\n\n")
{
    print "ok 4\n";
} else
{
    print "not ok 4: $result\nshould be:";
    print "\n  <quote preserve=\"#QUOTEME#\">\n    <quote><if expr=\"0\">0</if></quote>\n  </quote>\n\n";
}

$ifp = new HTML::Macro;
$ifp->set ('@precompile', 1);
$testloop = $ifp->new_loop ('testloop', 'dummy');
$testloop->push_hash ({'dummy' => 1});
$result = $ifp->process ('test5.html');
if ($result eq '<if expr="0">don\'t evaluate me</if>')
{
    print "ok 5\n";
} else
{
    print "not ok 5: $result\nshould be:";
    print '<if expr="0">don\'t evaluate me</if>';
    print "\ngot: $result\n";
}
