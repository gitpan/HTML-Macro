# HTML::Macro; Macro.pm
# Copyright (c) 2001 Michael Sokolov and Interactive Factory. All rights
# reserved. This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package HTML::Macro;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '1.14';


# Preloaded methods go here.

use HTML::Macro::Loop;
use Cwd;

# Autoload methods go after =cut, and are processed by the autosplit program.

# don't worry about hi-bit characters
my %char2htmlentity = 
(
    '&' => '&amp;',
    '>' => '&gt;',
    '<' => '&lt;',
    '"' => '&quot;',
);

sub html_encode
{
    $_[0] =~ s/([&><\"])/$char2htmlentity{$1}/g;
    return $_[0];
}

sub collapse_whitespace
{
    my ($buf, $blank_lines_only) = @_;
    my $out = '';
    my $pos = 0;
    my $protect_whitespace = '';
    while ($buf =~ m{(< \s*
                      (/?textarea|/?pre|/?quote)(_?)
                      (?: (?: \s+\w+ \s* = \s* "[^\"]*") |    # quoted attrs
                          (?: \s+\w+ \s* =[^>\"]) | # attrs w/ no quotes
                          (?: \s+\w+) # attrs with no value
                       ) *
                      >)}sgix)
    {
        my ($match, $tag, $underscore) = ($1, lc $2, $3);
        my $nextpos = pos $buf;
        if ($protect_whitespace)
        {
            $out .= substr ($buf, $pos, $nextpos - $pos);
        }
        else
        {
            my $chunk = substr ($buf, $pos, $nextpos - $pos);
            if (! $blank_lines_only) {
                 # collapse adj white space on a single line
                $chunk =~ s/\s+/ /g;
            }
            # remove blank lines and trailing whitespace; use UNIX line endings
            $chunk =~ s/\s*[\r\n]+/\n/sg;
            $out .= $chunk;
        }
        if ($tag eq "/$protect_whitespace") {
            $protect_whitespace = '';
        } elsif (! $protect_whitespace && $tag !~ m|^/|) {
            $protect_whitespace = $tag;
        }
    }

    # process trailing chunk
    $buf = substr ($buf, $pos) if $pos;
    if (! $blank_lines_only) {
        # collapse adj white space on a single line
        $buf =~ s/\s+/ /g;
    }
    # remove blank lines and trailing whitespace; use UNIX line endings
    $buf =~ s/\s*[\r\n]+/\n/sg;
    $out .= $buf;
}

sub doloop ($$)
{
    my ($self, $loop_id, $loop_body) = @_;

    my $p = $self;
    my $loop;
    while ($p) {
        $loop = $$p{$loop_id};
        last if $loop;
        # look for loops in outer scopes
        $p = $p->{'@parent'};
        last if !$p;
        $p = $p->{'@parent'};
        die if ! $p;
    }
    if (! $loop ) {
        $self->warning ("no match for loop id=$loop_id");
        return ;
    }
    if (!ref $loop || ! $loop->isa('HTML::Macro::Loop'))
    {
        $self->warning ("doloop: $loop (substitution for loop id \"$loop_id\") is not a HTML::Macro::Loop!");
        return ;
    }
    $loop_body = $loop->doloop ($loop_body);
    #$loop_body = $self->dosub ($loop_body);
    return $loop_body;
}

sub match_token ($$)
{
    my ($self, $var) = @_;

    # these are the two styles we've used
    my $val;
    while (1) 
    {
        $val = defined($$self{$var}) ? ($$self{$var})
                : ( defined ($$self{lc $var}) ? ($$self{lc $var})
                    : $$self{uc $var});
        last if (defined ($val));

        # include outer loops in scope
        my $parent = $self->{'@parent'} || '';
        last if !$parent;
        $self = $parent->{'@parent'};
        die if ! $self;
    }
    return defined($val) ? $val : undef;
}

sub dosub ($$)
{
    my ($self, $html) = @_;
    # replace any "word" surrounded by single or double hashmarks: "##".
    # Warning: two tokens of this sort placed right next to each other
    # are indistinguishable from a single token: #PAGE##NUM# could be one
    # token or two: #PAGE# followed by #NUM#.  This code breaks this ambiguity
    # by being greedy.  Probably should change it to be parsimonious and 
    # disallow hashmarks as part of tokens...

    my $lastpos = 0;
    if ($html =~ /((\#{1,2})(\w+)\2)/sg )
    {
        my ( $matchpos, $matchlen ) = (pos ($html), length ($1));
        my $result = substr ($html, 0, $matchpos - $matchlen);
        while (1)
        {
            my $quoteit = substr($2,1);
            my $var = $3;
            #warn "xxx $quoteit, $var: ($1,$2); (pos,len) = $matchpos, $matchlen";
            my $val = $self->match_token ($var);
            $result .= defined ($val) ? 
                ($quoteit ? &html_encode($val) : $val) : ($2 . $var . $2);
            $lastpos = $matchpos;
            if ($html !~ /\G.*?((\#{1,2})(\w+)\2)/sg)
            {
                $result .= substr ($html, $lastpos);
                return $result;
            }
            ( $matchpos, $matchlen ) = (pos ($html), length ($1));
            $result .= substr ($html, $lastpos,
                               $matchpos - $matchlen - $lastpos);
        }
    }
    return $html;
}

sub openfile
# follow the include path, looking for the file and return an open file handle
{
    my ($self, $fname) = @_;
    my @incpath = @ {$self->{'@incpath'}};
    unshift (@incpath, '.');
    while (my $dir = pop @incpath)
    {
        if (open (FILE, $dir . '/' . $fname))
        {
            # change directories so relative includes work
            # remember where we are so we can get back here

            my $cwd = cwd;
            push @ {$self->{'@cdpath'}}, $cwd;
            chdir ($dir);
            my (@path) = split m|/|, $fname;
            if (@path > 1)
            {
                my $dir = join '/', @path[0..$#path-1];
                chdir $dir || $self->error 
                    ("can't chdir $cwd/$dir to open $fname: $!");
                # $fname = $path[$#path];
            }

            return *FILE{IO};
        }
    }
    $self->error ("Cannot find $fname; incpath=". join ('; ', @ {$self->{'@incpath'}}));
    return undef;               # unreachable
}

sub doinclude ($$)
{
    my ($self, $include) = @_;
    my $lastpos = 0;
    $include = $self->dosub ($include);
    if ($include !~ m|<include/\s+file="(.*?)"\s*(asis)?\s*>|sgi)
    {
        $self->error ("bad include ($include)");
    }
    my ($filename, $asis) = ($1, $2);
    if ($asis)
    {
        #open (ASIS, $filename) || $self->error ("can't open $filename: $!");
        my $fh = $self->openfile ($filename);
        my $separator = $/;
        undef $/;
        my $result = <$fh>;
        $/ = $separator;

        close $fh;
        my $lastdir = pop @ {$self->{'@cdpath'}};
        chdir $lastdir;

        return $result;
    } else 
    {
        return $self->process ($filename);
    }
}

sub process_buf ($$)
{
    my ($self, $buf) = @_;
    my $out = '';
    my @tag_stack = ();
    my $pos = 0;
    my $quoting = 0;
    my $looping = 0;
    my $false = 0;
    my $emitting = 1;
    my $vanilla = 1;
    while ($buf =~ m{(< \s*
                      (/?loop|/?if|include/|/?else/?|/?quote)(_?)
                      (?: (?: \s+\w+ \s* = \s* "[^\"]*") |    # quoted attrs
                          (?: \s+\w+ \s* =[^>\"]) | # attrs w/ no quotes
                          (?: \s+\w+) # attrs with no value
                       ) *          
                      >)}sgix)
    {
        my ($match, $tag, $underscore) = ($1, lc $2, $3);
        next if ($self->{'@precompile'} && !$underscore);
        my $nextpos = (pos $buf) - (length ($match));
        $emitting = ! ($false || $looping);
        $vanilla = !($quoting || $false || $looping);
        if ($vanilla)
        {
            $out .= $self->dosub 
                (substr ($buf, $pos, $nextpos - $pos));
            # skip over the matched tag; handling any state changes below
            $pos = $nextpos + length($match);
        }
        elsif ($quoting)
        {
            # ignore everything except quote tags
            if ($tag eq '/quote')
            {
                my $matching_tag = pop @tag_stack;
                $self->error ("no match for tag 'quote'", $nextpos)
                    if (! $matching_tag);
                my ($start_tag, $attr) = @$matching_tag;
                $self->error ("start tag $start_tag ends with end tag 'quote'",
                        $nextpos)
                    if ($start_tag ne 'quote');
                if ($emitting && !$attr)
                {
                    # here we'ved popped out of a bunch of possibly nested 
                    # quotes: !$attr means this is the outermost one and
                    # $emitting means we're neither in a false condition nor
                    # are we in an accumulating loop (which will be processed
                    # later in a recursion).
                    
                    # the next line says to emit the </quote> tag if we are
                    # in a "preserved" quote:
                    my $endpos = ($quoting == 2) ? ($nextpos + length($match))
                        : $nextpos;
                    $out .= substr ($buf, $pos, $endpos - $pos);
                    $pos = $nextpos + length($match);
                }
                $quoting = $attr;
            }
            elsif ($tag eq 'quote')
            {
                push @tag_stack, [ 'quote', $quoting, $nextpos ];
            }
            next;
        }
        elsif (!$looping)
            # if looping, just match tags until we find the right matching 
            # end loop; don't process anything except quotes, since we might 
            # quote a loop tag!
            # Rather, leave that for a recursion.
        {
            # die if ! $false;    # debugging test
            # if we're in a false conditional, don't emit anything and skip over
            # the matched tag
            $pos = $nextpos + length($match);
        }
        if ($tag eq 'loop')
        {
            $match =~ /id="([^\"]*)"/ || $match =~ /id=(\S+)/;
            push @tag_stack, ['loop', $1, $nextpos];
            ++$looping;
            next;
        }
        if ($tag eq '/loop')
        {
            my $matching_tag = pop @tag_stack;
            $self->error ("no match for tag '$tag'", $nextpos)
                if ! $matching_tag;
            my ($start_tag, $attr, $tag_pos) = @$matching_tag;
            $self->error ("start tag '$start_tag' (at char $tag_pos) ends with end tag '$tag'",
                          $nextpos)
                if ($start_tag ne substr ($tag, 1));

            -- $looping;
            if (!$looping && !$quoting && !$false)
            {
                $out .= $self->doloop 
                    ($attr, substr ($buf, $pos, $nextpos-$pos));
                $pos = $nextpos + length($match);
            }
            next;
        }
        if ($tag eq 'quote')
        {
            push @tag_stack, ['quote', $quoting, $nextpos];
            if ($match =~ /preserve="([^\"]*)"/)
            {
                my $expr = $1 || '';
                $expr = $self->dosub ($expr);
                if (eval ( $expr ))
                {
                    $quoting = 2;
                    # why ?
                    $pos = $nextpos if !$looping;
                }
                else
                {
                    if ($match =~ /expr="([^\"]*)"/)
                    {
                        $expr = $1 || '';
                        $expr = $self->dosub ($expr);
                        if (eval ( $expr ))
                        {
                            $quoting = 1;
                        }
                    } else {
                        $quoting = 1;
                    }
                }
                if ($@) {
                    $self->error ("error evaluating $match (after substitutions: $expr): $@",
                            $nextpos);
                }
            } 
            else {
                $quoting = 1;
            }
            next;
        }
        if ($tag eq '/quote')
        {
            my $matching_tag = pop @tag_stack;
            $self->error ("no match for tag '$tag'", $nextpos)
                if ! $matching_tag;
            my ($start_tag, $attr, $tag_pos) = @$matching_tag;
            $self->error ("start tag '$start_tag' ends with end tag '$tag'",
                          $nextpos)
                if ($start_tag ne substr ($tag, 1));
            next;
        }
        next if $looping;       # ignore the rest of these tags while looping

        if (substr($tag, 0, 1) eq '/') 
            # process end tags; match w/start tags and handle state changes
        {
            my $matching_tag = pop @tag_stack;
            $self->error ("no match for tag '$tag'", $nextpos)
                if ! $matching_tag;
            my ($start_tag, $attr, $tag_pos) = @$matching_tag;
            $self->error ("start tag '$start_tag' ends with end tag '$tag'",
                          $nextpos)
                if ($start_tag ne substr ($tag, 1));

            if ($start_tag eq 'if')
            {
                $false = $attr;
            }
            next;
        }
        if ($tag eq 'if')
        {
            push @tag_stack, ['if', $false, $nextpos] ;
            if ($vanilla) 
            {
                $match =~ /expr="(.*)"/;
                my $expr = $1 || '';
                $expr = $self->dosub ($expr);
                $false = ! eval ( $expr );
                if ($@) {
                    $self->error ("error evaluating $match (after substitutions: $expr): $@",
                            $nextpos);
                }
            }
            next;
        }
        if ($tag eq 'else/')
        {
            my $top = $tag_stack[$#tag_stack];
            $self->error ("<else/> not in <if>", $nextpos) 
                if ($$top[0] ne 'if');
            # if we are embedded in a false condition, it overrides us: 
            # don't change false based on this else.  Also, don't evaluate
            # anything while looping: postpone for recursion.
            if (!$looping && ! $$top[1])
            {
                $false = ! $false ;
            }
            next;
        }
        if ($tag eq 'else')
        {
            my $top = $tag_stack[$#tag_stack];
            $self->error ("<else> not in <if>", $nextpos) if $$top[0] ne 'if';
            $false = ! $false if (!$looping && ! $$top[1]);
            push @tag_stack, ['else', $false];
            next;
        }
        if ($tag eq 'include/')
        {
            my $file = $self->{'@file'};
            $out .= $self->doinclude ($match) if ($vanilla);
            $self->{'@file'} = $file;
            next;
        }

    }
    # process trailer
    if ($quoting || $looping || $false)
    {
        my $tag = pop @tag_stack;
        $self->error ("EOF while still looking for close tag for " . $$tag[0]
                      . '(' . $$tag[1] .')', $$tag[2]);
    }
    $out .= $self->dosub (substr ($buf, $pos));
    if ($self->{'@collapse_whitespace'})
    {
        # collapse adjacent white space
        $out = &collapse_whitespace ($out, undef);
    }
    elsif ($self->{'@collapse_blank_lines'})
    {
        # remove blank lines
        $out = &collapse_whitespace ($out, 1);
    }
    return $out;
}

sub process ($$)
{
    my ($self, $fname) = @_;

    my $fh = $self->openfile ($fname);

    #open (HTML, $fname) || $self->error ("can't open $fname: $!");
    my $separator = $/;
    undef $/;
    my $html = <$fh>;
    $/ = $separator;
    close $fh;

    # for error reporting
    $self->{'@file'} = $fname;

    warn "nothing read from $fname" if ! $html;
    my $result =  $self->process_buf ($html);
    
    my $lastdir = pop @ {$self->{'@cdpath'}};
    chdir $lastdir;

    return $result;
}

sub print ($$)
{
    # warn "gosub $_[0] \n";
    my ($self, $fname) = @_;

    print "Cache-Control: no-cache\n";
    print "Pragma: no-cache\n";
    print "Content-Type: text/html\n\n";
    print $self->process ($fname);
}

sub error
{
    my ($self, $msg, $pos) = @_;
    $msg = "HTML::Macro: $msg";
    $msg .= " in file " . $self->{'@file'} if ($self->{'@file'});
    $msg .= " near char $pos" if $pos;
    die "$msg\n";
}

sub warning
{
    my ($self, $msg, $pos) = @_;
    $msg = "HTML::Macro: $msg";
    $msg .= " in file " . $self->{'@file'} if ($self->{'@file'});
    $msg .= " near char $pos" if $pos;
    warn "$msg\n";
}

sub set ($$)
{
    my $self = shift;
    while ($#_ > 0) {
        $$self {$_[0]} = $_[1];
        shift;
        shift;
    }
    warn "odd number of arguments to set" if @_;
}

sub push_incpath ($ )
{
    my ($self, $dir) = @_;
    if (substr($dir,0,1) ne '/')
    {
        # turn into an absolute path if not already
        $dir = cwd . '/' . $dir;
    }
    push @ {$self->{'@incpath'}}, $dir;
}

sub set_hash ($ )
{
    my ($self, $hash) = @_;
    while (my ($var, $val) = each %$hash)
    {
        $$self {$var} = defined($val) ? $val : '';
    }
}

sub get ($ )
{
    my ($self, $var) = @_;
    return $$self {$var};
}

sub declare ($@)
# use this to indicate which vars are expected on this page.
# Just initializes the hash to have zero for all of its args
{
    my ($self, @vars) = @_;
    @$self {@vars} = ('') x @vars;
}

sub new ($ )
{
    my ($class) = @_;
    my $self = { };
    $self->{'@incpath'} = [];
    bless $self, $class;
    return $self;
}

sub new_loop ()
{
    my ($self, $name, @loop_vars) = @_;
    my $new_loop = HTML::Macro::Loop->new($self);
    if ($name) {
        $self->set ($name, $new_loop);
        if (@loop_vars) {
            $new_loop->declare (@loop_vars);
        }
    }
    return $new_loop;
}

1;
__END__

=head1 NAME

HTML::Macro - generate dynamic HTML pages using templates

=head1 SYNOPSIS

  use HTML::Macro;
  $ifp = HTML::Macro->new();
  $ifp->declare ('var', 'missing');
  $ifp->set ('var', 'value');
  $ifp->print ('test.html');

=head1 DESCRIPTION

HTML::Macro is a module to be used behind a web server (in CGI scripts). It
provides a convenient mechanism for generating HTML pages by combining
"dynamic" data derived from a database or other computation with HTML
templates that represent fixed or "static" content of a page.

There are many different ways to accomplish what HTML::Macro does, including
ASP, embedded perl, CFML, etc, etc. The motivation behind HTML::Macro is to keep
everything that a graphic designer wants to play with *in a single HTML
template*, and to keep as much as possible of what a perl programmer wants
to play with *in a perl file*.  Our thinking is that there are two
basically dissimilar tasks involved in producing a dynamic web page:
graphic design and programming. Even if one person is responsible for both
tasks, it is useful to separate them in order to aid clear thinking and
organized work.  I guess you could say the main motivation for this
separation is to make it easier for emacs (and other text processors,
including humans) to parse your files: it's yucky to have a lot of HTML in
a string in your perl file, and it's yucky to have perl embedded in a
special tag in an HTML file.

That said, HTML::Macro does provide for some simple programming constructs to
appear embedded in HTML code.  Think of it as a programming language on a
similar level as the C preprocessor.  HTML::Macro "code" is made to look like
HTML tags so it will be fairly innocuous for most HTML-oriented editors to
deal with.  At the moment HTML::Macro suports variables, conditionals, loops,
file interpolation and quoting (to inhibit all of the above).  HTML::Macro
variables are always surrounded with single or double hash marks: "#" or
"##".  Variables surrounded by double hash marks are subject to html entity
encoding; variables with single hash marks are substituted "as is" (like
single quotes in perl or UNIX shells).  Conditionals are denoted by the
<if> and <else> tags, and loops by the <loop> tag.

Usage:

Create a new HTML::Macro:
  $ifp = HTML::Macro->new();

Optionally, declare the names of all the variables that will be substituted
on this page.  This has the effect of defining the value '' for all these
variables.
  $ifp->declare ('var', 'missing');

Set the values of one or more variables using HTML::Macro::set.

  $ifp->set ('var', 'value');

Or use IF:Page::set_hash to set a whole bunch of values at once.  Typically
used with the value returned from a DBI::fetchrow_hashref.

  $ifp->set_hash ( {'var' => 'value' } );

Finally, process the template and print the result using HTML::Macro::print,
or save the value return by HTML::Macro::process.  

    open CACHED_PAGE, '>page.html';
    print CACHED_PAGE, $ifp->process ('templates/page_template.html');
    close CACHED_PAGE;
 
    - or - 

    $ifp->print ('test.html');

As a convenience the IF:Page::print function prints the processed template
that would be returned by HTML::Macro::process, preceded by appropriate HTTP
headers (Content-Type and no-cache directives).

HTML::Macro::process attempts to perform a substitution on any word beginning
and ending with single or double hashmarks (#) , such as ##NAME##.
A word is any sequence of alphanumerics and underscores.  If the
HTML::Macro has a matching variable, its value is substituted for the word in
the template everywhere it appears.  A matching variable may match the
template word literally, or it may match one of the following:

the word with the delimiting hash marks stripped off ('NAME' in the example)
the word without delimiters lowercased ('name')
the word without delimiters uppercased ('NAME')

A typical usage is to stuff all the values returned from
DBI::fetchrow_hashref into an HTML::Macro.  Then SQL column names are to be
mapped to template variables.  Databases have different case conventions
for column names; providing the case insensitivity and stripping the
underscores allows templates to be written in a portable fashion while
preserving an upper-case convention for template variables.

HTML entity quoting

Variables surrounded by double delimiters are subject to HTML entity encoding.
That is, >, < and ""  occuring in the variables value are replaced by their
corresponding HTML entities.  Variables surrounded by single delimiters are not
quoted; they are substituted "as is"

Conditionals

Conditional tags take one of the following forms:

<if expr="perl expression"> 
 HTML block 1
<else/>
 HTML block 2
</if>

or

<if expr="perl expression"> 
 HTML block 1
<else>
 HTML block 2
</else>
</if>

or simply

<if expr="perl expression"> 
 HTML block 1
</if>

Conditional tags are processed by evaluating the value of the "expr"
attribute as a perl expression.  The entire conditional tag structure is
replaced by the HTML in the first block if the expression is true, or the
second block (or nothing if there is no else clause) if the expressin is
false.

Conditional expressions are subject to variable substitution, allowing for
constructs such as:

You have #NUM_ITEMS# item<if "#NUM_THINGS# > 1">s</if> in your basket.

File Interpolation

It is often helpful to structure HTML by separating commonly-used chunks
(headers, footers, etc) into separate files.  HTML::Macro provides the
<include/> tag for this purpose.  Markup such as <include/
file="file.html"> gets replaced by the contents of file.html, which is
itself subject to evaluation by HTML::Macro.  If the "asis" attribute is
present: <include/ file="quoteme.html" asis>, the file is included "as is";
without any further evaluation.

Also, HTML::Macro provides support for an include path.  This allows common
"part" files to be placed in a common place.  HTML::Macro::push_incpath adds
to the path, as in $ifp->push_incpath ("/path/to/include/files").  The
current directory (of the file being processed) is always checked first,
followed by each directory on the incpath.  When paths are added to the
incpath they are always converted to absolute paths, relative to the
working directory of the invoking script.  Thus, if your script is running
in "/cgi-bin" and calls push_incpath("include"), this adds
"/cgi-bin/include" to the incpath.

Quoting

The preceding transformations can be inhibited by the use of the "<quote>"
tag.  Any markup enclosed by <quote> ... </quote> is passed on as-is.
quote tags may be nested to provide for multiple passes of macro
substitution.

    This could be useful if you need to include markup like <if> in your
    output, although that could be more easily accomplished by the usual
    HTML entity encodings: escaping < with &lt; and so on.  The real reason
    this is here is to enable multiple passes of HTML::Macro to run on "proto"
    templates that just generate other templates.

Quote tags have an optional "preserve" attribute.  If "preserve" is
present, its value is evaluated (as with if above), and if the result is
true, the quote tag is preserved in the output.  Otherwise, the tag is
swallowed and the quoting behavior is inhibited.  So:

<quote preserve="1">xyzzy<include/ file="foo"></quote>  

would be passed over unchanged,

and

<quote preserve="0"><include/ file="foo"></quote>

would be replaced by the contents of the file named "foo".

Loops

Finally, the <loop> tag provides for repeated blocks of HTML, with
subsequent iterations evaluated in different contexts.  For more about
loops, see the IF:Page::Loop documentation.


HTML::Macro is copyright (c) 2000 by Michael Sokolov and Interactive Factory
(sm).  All rights are reserved.

=head1 AUTHOR

Michael Sokolov, sokolov@ifactory.com

=head1 SEE ALSO HTML::Macro::Loop

perl(1).

=cut
