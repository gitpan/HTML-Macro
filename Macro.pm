# HTML::Macro; Macro.pm
# Copyright (c) 2001,2002 Michael Sokolov and Interactive Factory. Some rights
# reserved. This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package HTML::Macro;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %file_cache);

require Exporter;
require AutoLoader;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(
	
);
$VERSION = '1.21';


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
        $pos = $nextpos;
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

sub process_cf_quotes
{
    my ($pbuf) = @_;
    $$pbuf =~ s/<!---.*?--->//sg;
}

sub doloop ($$)
{
    my ($self, $loop_id, $loop_body) = @_;

    if ($self->{'@attr'}->{'debug'}) {
        print STDERR "HTML::Macro: processing loop $loop_id\n";
    }
    my $p = $self;
    my $loop;
    while ($p) {
        $loop = $$p{$loop_id};
        last if $loop;
        # look for loops in outer scopes
        $p = $p->{'@parent'};
        last if !$p;
        if ($p->isa('HTML::Macro::Loop'))
        {
            $p = $p->{'@parent'};
            die if ! $p;
        }
    }
    if (! $loop ) {
        $self->warning ("no match for loop id=$loop_id");
        return '';
    }
    if (!ref $loop || ! $loop->isa('HTML::Macro::Loop'))
    {
        $self->error ("doloop: $loop (substitution for loop id \"$loop_id\") is not a HTML::Macro::Loop!");
    }
    $loop_body = $loop->doloop ($loop_body);
    #$loop_body = $self->dosub ($loop_body);
    return $loop_body;
}

sub doeval ($$)
{
    my ($self, $expr, $body) = @_;
    if ($self->{'@attr'}->{'debug'}) {
        print STDERR "HTML::Macro: processing eval: { $expr }\n";
    }
    my $nested = new HTML::Macro;
    $nested->{'@parent'} = $self;
    $nested->{'@body'} = $body;
    my @incpath = @ {$self->{'@incpath'}};
    $nested->{'@incpath'} = \@incpath; # make a copy of incpath
    $nested->{'@attr'} = $self->{'@attr'};
    $nested->{'@cwd'} = $self->{'@cwd'};

    my $package = $self->{'@caller_package'};
    my $result = eval " & {package $package; sub { $expr } } (\$nested)";
    if ($@) {
        $self->error ("error evaluating '$expr': $@");
    }
    return $result;
}

sub match_token ($$)
{
    my ($self, $var) = @_;

    if ($self->{'@attr'}->{'debug'}) {
        print STDERR "HTML::Macro: matching token $var\n";
    }
    # these are the two styles we've used
    my $val;
    while (1) 
    {
        $val = exists($$self{$var}) ? (defined($$self{$var}) ?  $$self{$var} : '')
                : ( exists ($$self{lc $var}) ? (defined($$self{lc $var}) ? $$self{lc $var} : '')
                    : (exists $$self{uc $var} ? (defined($$self{uc $var}) ? $$self{uc $var} : '')
                       : undef) );
        last if (defined ($val));

        # include outer loops in scope
        my $parent = $self->{'@parent'} || '';
        last if !$parent;
        # parent may be either an HTML::Macro or an HTML::Macro::Loop
        if ($parent->isa('HTML::Macro::Loop'))
        {
            $self = $parent->{'@parent'};
            die if ! $self;
        } else {
            $self = $parent;
        }
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

sub findfile
# follow the include path, looking for the file and return an open file handle
{
    my ($self, $fname) = @_;
    my @incpath = @ {$self->{'@incpath'}};
    unshift (@incpath, '') unless ($self->{'@no_local_incpath'});
    while (@incpath)
    {
        my $dir = shift @incpath;
        my @stat = stat $dir . $fname;
        return ($dir . $fname, $stat[9]) if @stat;
    }
    @incpath = @ {$self->{'@incpath'}};
    $self->error ("Cannot find file $fname, incpath=" . join (',',@incpath)
                  . "cwd=" . cwd);
    return ();
}

sub openfile
# open the file, change directories to the file's directory, remembering where
# we came from, and add the file's directory to incpath
{
    my ($self, $path) = @_;
    my @incpath = @ {$self->{'@incpath'}};

    open (FILE, $path) || 
        $self->error ("Cannot open '$path': $!");

    if ($self->{'@attr'}->{'debug'}) {
        print STDERR "HTML::Macro: opening $path, incpath=@incpath, cwd=", cwd, "\n";
    }
    $self->{'@file'} = $path;

    # change directories so relative includes work
    # remember where we are so we can get back here

    my $cwd = $self->{'@cwd'} || cwd; # cwd is expensive
    push @ {$self->{'@cdpath'}}, $cwd;

    my ($dir, $fname);
    if ($path =~ m|(.*)/([^/])+$|) {
        ($dir, $fname) = ($1, $2);
    } else {
        ($dir, $fname) = ('', $path);
    }

    # add our current directory to incpath so includes from other directories
    # will still look here - if $dir is not an absolute path.  Recognizes
    # drive letters even if this is !Windows. oh well

    $dir = "$cwd/$dir" if ($dir !~ m|^([A-Za-z]:)?/|);
    $dir =~ s|//+|/|g;          # remove double slashes

    push @ {$self->{'@incpath'}}, $dir;

    # chdir to where file is
    chdir $dir || $self->error ("openfile can't chdir $dir (opening $path): $!");

    #print STDERR "openfile: \@cwd=", $dir, "\n";
    $self->{'@cwd'} = $dir;

    return *FILE{IO};
}

sub doinclude ($$)
{
    my ($self, $include) = @_;
    my $lastpos = 0;
    $include = $self->dosub ($include);
    if ($include !~ m|<include_?/\s+file="(.*?)"\s*(asis)?\s*>|sgi)
    {
        $self->error ("bad include ($include)");
    }
    my ($filename, $asis) = ($1, $2);
    if ($asis)
    {
        #open (ASIS, $filename) || $self->error ("can't open $filename: $!");
        
        my $buf = $self->readfile ($filename);

        my $lastdir = pop @ {$self->{'@cdpath'}};
        if ($lastdir)
        {
            chdir $lastdir ;
            $self->{'@cwd'} = $lastdir;
        }
        else {
            delete $self->{'@cwd'};
        }
        pop @ {$self->{'@incpath'}};

        return $buf;
    } else 
    {
        return $self->process ($filename);
    }
}

sub attr_backwards_compat
{
    my ($self) = @_;
    my $attr = $self->{'@attr'};
    foreach my $key ('debug', 'collapse_whitespace', 'collapse_blank_lines',
                     'precompile')
    {
        $$attr{$key} = $$self{'@' . $key} if defined $$self{'@' . $key};
    }
}

sub process_buf ($$)
{
    my ($self, $buf) = @_;
    return '' if ! $buf;
    my $out = '';
    my @tag_stack = ();
    my $pos = 0;
    my $quoting = 0;
    my $looping = 0;
    my $false = 0;
    my $emitting = 1;
    my $vanilla = 1;

    &attr_backwards_compat;

    my $underscore = $self->{'@attr'}->{'precompile'} ? '_' : '';
    print STDERR "Entering process_buf\n" if ($self->{'@attr'}->{'debug'});

    $self->get_caller_info if ! $self->{'@caller_package'};
    my $package = $self->{'@caller_package'};

    while ($buf =~ m{(< \s*
                      (/?loop|/?if|include|/?else|/?quote|/?eval|define)$underscore(/?)
                      (   (?: \s+\w+ \s* = \s* "[^\"]*") |    # quoted attrs
                          (?: \s+\w+ \s* =[^>\"]) | # attrs w/ no quotes
                          (?: \s+\w+) # attrs with no value
                       ) * \s*         
                      (/?)>)}sgix)
    {
        my ($match, $tag, $slash, $attrs, $slash2) = ($1, lc $2, $3, $4, $5);
        my $nextpos = (pos $buf) - (length ($&));
        $slash = $slash2 if ! $slash; # allow normal XML style
        if (! $slash && ($tag eq 'include' || $tag eq 'define'))
        {
            $slash = 1;
            $self->warning ("missing trailing slash for $tag", $nextpos);
        }
        $tag .= '/' if $slash;
        $emitting = ! ($false || $looping);
        $vanilla = !($quoting || $false || $looping);
        if ($vanilla)
        {
            $out .= $self->dosub 
                (substr ($buf, $pos, $nextpos - $pos));
            # skip over the matched tag; handling any state changes below
            $pos = $nextpos + length($&);
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
        if ($tag eq 'loop' || $tag eq 'eval')
            # loop and eval are similar in their syntactic force - both are block-level
            # tags that force embedded scopes.  Therefore their contents are processed
            # in a nested evaluation, and not here.
        {
            (($tag eq 'loop') &&
             $match =~ /id="([^\"]*)"/ || $match =~ /id=(\S+)/) ||
                 # (tag eq 'eval') &&
                 $match =~ /expr="([^\"]*)"/ ||
                     $self->error ("$tag tag has no id '$match'", $nextpos);
            push @tag_stack, [$tag, $1, $nextpos];
            ++$looping;
            next;
        }
        if ($tag eq '/loop' || $tag eq '/eval')
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
                $attr = $self->dosub ($attr);
                if ($tag eq '/loop') {
                    $out .= $self->doloop 
                        ($attr, substr ($buf, $pos, $nextpos-$pos));
                } else {
                    # tag=eval
                    $out .= $self->doeval
                        ($attr, substr ($buf, $pos, $nextpos-$pos));
                }
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
                my $result = eval "{ package $package; $expr }";
                if ($result)
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
                        $result = eval "{ package $package; $expr }";
                        if ($result)
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
                if ($attrs =~ /^\s* expr \s* = \s* "([^\"]*)" \s*$/six)
                { 
                    my $expr = $1 || '';
                    $expr = $self->dosub ($expr);
                    $false = !eval "{ package $package; $expr }";
                    if ($@) {
                        $self->error ("error evaluating $match (after substitutions: $expr): $@",
                                      $nextpos);
                    }
                } 
                elsif ($attrs =~ /^\s* def \s* = \s* "([^\"]*)" \s*$/six)
                {
                    my $token = $1 || '';
                    $false = ! $self->match_token ($token);
                }
                else
                {
                    $self->error ("error parsing 'if' attributes: $attrs)",
                                  $nextpos);
                }
            }
            next;
        }
        elsif ($tag eq 'else/')
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
        elsif ($tag eq 'else')
        {
            my $top = $tag_stack[$#tag_stack];
            $self->error ("<else> not in <if>", $nextpos) if $$top[0] ne 'if';
            $false = ! $false if (!$looping && ! $$top[1]);
            push @tag_stack, ['else', $false];
            next;
        }
        elsif ($tag eq 'include/')
        {
            my $file = $self->{'@file'};
            $out .= $self->doinclude ($match) if ($vanilla);
            $self->{'@file'} = $file;
            next;
        }
        elsif ($tag eq 'define/')
        {
            if (!$looping && !$quoting && !$false)
            {
                $match =~ /name="([^\"]*)"/ || 
                    $self->error ("no name attr for define tag in '$match'",
                                  $nextpos);
                my ($name) = $1;
                $match =~ /value="([^\"]*)"/ || 
                    $self->error ("no value attr for define tag in '$match'",
                                  $nextpos);
                my ($val) = $1;
                $self->set ($name, $self->dosub($val));
            }
        }

    }
    # process trailer
    #if ($quoting || $looping || $false)
    while (@tag_stack)
    {
        my $tag = pop @tag_stack;
        $self->error ("EOF while still looking for close tag for " . $$tag[0]
                      . '(' . $$tag[1] .')', $$tag[2]);
    }
    $out .= $self->dosub (substr ($buf, $pos));
    print STDERR "Exiting process_buf\n" if ($self->{'@attr'}->{'debug'});
    # remove extra whitespace

    if ($self->{'@attr'}->{'collapse_whitespace'})
    {
        # collapse adjacent white space
        $out = &collapse_whitespace ($out, undef);
    }
    elsif ($self->{'@attr'}->{'collapse_blank_lines'})
    {
        # remove blank lines
        $out = &collapse_whitespace ($out, 1);
    }

    return $out;
}

sub readfile
{
    my ($self, $fname) = @_;

    $self->{'@cwd'} = cwd if ! $self->{'@cwd'};
    my $cwd = $self->{'@cwd'};
    my $key = $cwd . '/' . $fname;

    my ($path, $mtime) = $self->findfile ($fname);
    if (!$path) {
        $self->error ("$fname not found: incpath=(" . join (',',@{$$self{'@incpath'}}) . ")");
        return;
    }
    if ($self->{'@attr'}->{'cache_files'} && exists $file_cache{$key}
        && $file_cache{$key .  '@mtime'} >= $mtime)
    {
        #print STDERR "readfile CACHED (file=", $$self{'@file'}, ") $key\n";

        # the name of the file
        $$self{'@file'} = $file_cache{$key . '@file'};

        # the absolute path of the file's directory
        push @{$$self{'@incpath'}}, $file_cache{$key . '@incpath_new'};

        # the absolute path of the enclosing file's directory;
        # where we chdir when we're done processing this file
        push @{$$self{'@cdpath'}}, $file_cache{$key . '@cdpath_new'};

        # Isn't this also the absolute path of the file's directory?
        $$self{'@cwd'} = $file_cache{$key . '@cwd'};

        chdir $$self{'@cwd'};

        # return the contents of the file
        return $file_cache{$key};
    }

    #print STDERR "readfile $key\n";
    my $fh = $self->openfile ($path);

    #open (HTML, $fname) || $self->error ("can't open $fname: $!");
    my $separator = $/;
    undef $/;
    my $body = <$fh>;
    $/ = $separator;
    close $fh;

    # remove CFM-style quotes: <!--- ... --->
    &process_cf_quotes (\$body);


    # remove extra whitespace
    if ($self->{'@attr'}->{'collapse_whitespace'})
    {
        # collapse adjacent white space
        $body = &collapse_whitespace ($body, undef);
    }
    elsif ($self->{'@attr'}->{'collapse_blank_lines'})
    {
        # remove blank lines
        $body = &collapse_whitespace ($body, 1);
    }

    if ($self->{'@attr'}->{'cache_files'})
    {
        $file_cache{$key} = $body;
        $file_cache{$key . '@file'} = $$self{'@file'};
        my $list = $$self{'@incpath'};
        $file_cache{$key . '@incpath_new'} = $$list[$#$list];
        $list = $$self{'@cdpath'};
        $file_cache{$key . '@cdpath_new'} = $$list[$#$list];
        $file_cache{$key . '@cwd'} = $$self{'@cwd'};
        $file_cache{$key .  '@mtime'} = $mtime;
    }
    return $body;
    #print STDERR "cwd=", $$self{'@cwd'}, "\n";

    #warn "nothing read from $fname" if ! $$self{'@body'};
}

sub process ($$)
{
    my ($self, $fname) = @_;

    &attr_backwards_compat;

    $$self{'@body'} = &readfile ($self, $fname) if ($fname);

    my $result =  $self->process_buf ($$self{'@body'});
    
    my $lastdir = pop @ {$self->{'@cdpath'}};
    if ($lastdir)
    {
        #print STDERR "popping up to $lastdir\n";
        chdir $lastdir ;
        $self->{'@cwd'} = $lastdir;
    }
    else {
        delete $self->{'@cwd'};
    }
    pop @ {$self->{'@incpath'}};

    return $result;
}

sub print ($$)
{
    # warn "gosub $_[0] \n";
    my ($self, $fname) = @_;

    print "Cache-Control: no-cache\n";
    print "Pragma: no-cache\n";
    print "Content-Type: text/html\n\n";
    print &process;
}

sub error
{
    my ($self, $msg, $pos) = @_;
    $self->get_caller_info if ! $self->{'@caller_package'};
    $msg = "HTML::Macro: $msg";
    $msg .= " parsing " . $self->{'@file'} if ($self->{'@file'});
    $msg .= " near char $pos" if $pos;
    die "$msg\ncalled from " . $self->{'@caller_file'} . ", line " . $self->{'@caller_line'} . "\n";
}

sub warning
{
    my ($self, $msg, $pos) = @_;
    $self->get_caller_info if ! $self->{'@caller_package'};
    $msg = "HTML::Macro: $msg";
    $msg .= " parsing " . $self->{'@file'} if ($self->{'@file'});
    $msg .= " near char $pos" if $pos;
    warn "$msg\ncalled from " . $self->{'@caller_file'} . ", line " . $self->{'@caller_line'} . "\n";
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
    my ($self) = shift;
    while (my $dir = shift)
    {
        $dir .= '/' if $dir !~ m|/$|;
        if ($dir !~  m|^(?:[A-Za-z]:)?/|)
        {
            # turn into an absolute path if not already
            # allow DOS drive letters at the start
            $dir = ($self->{'@cwd'} || cwd) . '/' . $dir;
        }
        push @ {$self->{'@incpath'}}, $dir;
    }
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
# finds values in enclosing scopes and uses macro case-collapsing rules; ie
# matches $var, $uc var, or lc $var
{
    my ($self, $var) = @_;
    return $self->match_token ($var);
}

sub declare ($@)
# use this to indicate which vars are expected on this page.
# Just initializes the hash to have zero for all of its args
{
    my ($self, @vars) = @_;
    @$self {@vars} = ('') x @vars;
}

sub get_caller_info ($ )
{
    my ($self) = @_;
    my ($caller_file, $caller_line);
    my $stack_count = 0;
    my $pkg;
    do {
        ($pkg, $caller_file, $caller_line) = caller ($stack_count++);
    }
    # ignore HTML::Macro and HTML::Macro::Loop
    while ($pkg =~ /HTML::Macro/);

    $self->{'@caller_package'} = $pkg;
    $self->{'@caller_file'} = $caller_file;
    $self->{'@caller_line'} = $caller_line;
}

sub new ($$$ )
{
    my ($class, $fname, $attr) = @_;
    my $self = { };
    $self->{'@incpath'} = [];

    if ($attr) {
        if (ref $attr ne 'HASH') {
            $self->error ('third argument (attr) to new must be hash ref');
        }
        $self->{'@attr'} = $attr;
    } else {
        $self->{'@attr'} = {};
    }

    bless $self, $class;

    $$self{'@body'} = &readfile($self, $fname) if ($fname);

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

sub keys ()
{
    my ($self) = @_;
    my @keys = grep /^[^@]/, keys %$self;
    push @keys, $self->{'@parent'}->keys() if $self->{'@parent'};
    return @keys;
}

1;
__END__

=head1 NAME

HTML::Macro - process HTML templates with loops, conditionals, macros and more!

=head1 SYNOPSIS

  use HTML::Macro;
  $htm = new HTML::Macro ('template.html');
  $htm->print;

  sub myfunc {
    $htm->declare ('var', 'missing');
    $htm->set ('var', 'value');
    return $htm->process;
  }

  ( in template.html ):

  <html><body>
    <eval expr="&myfunc">
      <if def="missing">
        Message about missing stuff...
      <else />
        Var's value is #var#.
      </if>
    </eval>
  </body></html>

=head1 DESCRIPTION

HTML::Macro is a module to be used behind a web server (in CGI scripts). It
provides a convenient mechanism for generating HTML pages by combining
"dynamic" data derived from a database or other computation with HTML
templates that represent fixed or "static" content of a page.

There are many different ways to accomplish what HTML::Macro does,
including ASP, embedded perl, CFML, etc, etc. The motivation behind
HTML::Macro is to keep everything that a graphic designer wants to play
with *in a single HTML template*, and to keep as much as possible of what a
perl programmer wants to play with *in a perl file*.  Our thinking is that
there are two basically dissimilar tasks involved in producing a dynamic
web page: graphic design and programming. Even if one person is responsible
for both tasks, it is useful to separate them in order to aid clear
thinking and organized work.  I guess you could say the main motivation for
this separation is to make it easier for emacs (and other text processors,
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

    $htm = new HTML::Macro  ('templates/page_template.html');

The filename argument is optional.  If you do not specify it now, you can
do it later, which might be useful if you want to use this HTML::Macro to
operate on more than one template.  If you do specify the template when the
object is created, the file is read in to memory at that time.

Optionally, declare the names of all the variables that will be substituted
on this page.  This has the effect of defining the value '' for all these
variables.

  $htm->declare ('var', 'missing');

Set the values of one or more variables using HTML::Macro::set.

  $htm->set ('var', 'value');

Or use HTML::Macro::set_hash to set a whole bunch of values at once.  Typically
used with the value returned from a DBI::fetchrow_hashref.

  $htm->set_hash ( {'var' => 'value' } );

Finally, process the template and print the result using HTML::Macro::print,
or save the value return by HTML::Macro::process.  

    open CACHED_PAGE, '>page.html';
    print CACHED_PAGE, $htm->process;
    # or: print CACHED_PAGE, $htm->process ('templates/page_template.html');
    close CACHED_PAGE;
 
    - or - 

    $htm->print;

    - or -

    $htm->print ('test.html');

As a convenience the HTML::Macro::print function prints the processed template
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
to the path, as in $htm->push_incpath ("/path/to/include/files").  The
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

The <loop> tag provides for repeated blocks of HTML, with
subsequent iterations evaluated in different contexts.  For more about
loops, see the IF:Page::Loop documentation.

New in 1.21:

Now allow normal XML-style for non-matched tags (like <else/> - we used to
allow <else/ > and not <else />; now we allow both.

New in 1.20; 

File cache now respects modification times, reloading modified files.

Attribute handling was changed.  You should now specify attributes as a
hash ref arg to new (like DBI).  Attributes to be specified (without a
preceding '@') may be: collapse_whitespace, collapse_blank_lines, debug and
precompile. 

Collapse_whitespace is now called when loading (caching) files, for
further optimization.  This means interpolated values are no longer
collapsed; also any files read in by the user are not subject to
collapsing.

ColdFusion style quotes (<!--- ... --->) are now processed (by removing them).
The processing is done when a file is read.


New in 1.19; Various performance enhancements, including file caching.
Included files, and templates read by HTML::Macro::new and process are
cached in memory if the 'cache_files' attribute is true.  This can improve
performance significantly if you include a file in a loop that is repeated
often.  No attempt is made to detect when a file changes, so this cache is
unsuitable for use with mod_perl.  I plan to add cache freshening at some
point for just this reason.

collapse_whitespace is now only called on the "final" pass of evaluation,
saving considerable work.  Also, we attempt to make lighter use of cwd,
which turns out to be expensive in many OS implementations since it calls
`pwd`.  I am considering a rewrite of the entire mechanism for walking
directories, but at least it runs reasonably fast now when you have a lot
of includes.

<eval/>: embedded perl evaluation

New in 1.15, the <eval expr=""></eval> construct evaluates its expression
attribute as Perl, in the package in which the HTML::Macro was created.
This is designed to allow you to call out to a perl function, not to embed
large blocks of code in the middle of your HTML, which we do not advocate.
The expression attribute is treated as a Perl block (enclosed in curly
braces) and passed a single argument: an HTML::Macro object whose content
is the markup between the <eval> and </eval> tags, and whose attributes are
inherited from the enclosing HTML::Macro.  The return value of the
expression is interpolated into the output.  A typical use might be:

Your user profile:
<eval expr="&get_user_info">
  #FIRST_NAME# #LAST_NAME# <br>
  #ADDRESS## #CITY# #STATE# <br>
</eval>

where get_user_info is a function defined in the package that called
HTML::Macro::process (or process_buf, or print...).  Presumably get_user_info will look something like:

sub get_user_info
{
    my ($htm) = @_;
    my $id = $htm->get ('user_id');
    ... get database record for user with id $id ...;
    $htm->set ('first_name', ...);
    ...;
    return $htm->process;
}

Note that the syntax
used to call the function makes use of a special Perl feature that the @_ variable is automatically passed as an arg list when you use & and not () in the function call: a more explicit syntax would be:

  <eval expr="&get_user_info(@_)">...


<define />

You can use the <define/> tag, as in:

 <define/ name="variable_name" value="variable_value">  

to define HTML::Macro tags during the course of processing.  These
definitions are processed in the same macro evaluation pass as all the
other tags.  Hence the defined variable is only in scope after the
definition, and any redefinition will override, in the way that you would
expect.

This feature is useful for passing arguments to functions called by eval.

New in version 1.14:

- The quote tag is now deprecated.  In its place, you should use tags with
  an underscore appended to indicate tags to be processed by a
  preprocessor.  Indicate that this is a preprocessing pass by setting the
  variable '@precompile' to something true.  For example: <if_ expr="0">I
  am a comment to be removed by a preprocessor.</if_> <if expr="#num# >
  10">this if will be left unevaluated by a preprocessor.</if>

- Support for testing for the existence of a variable is now provided by
  the if "def" attribute.  You used to have to do a test on the value of
  the variable, which sometimes caused problems if the variable was a
  complicated string with quotes in it.  Now you can say:

  <if def="var"><b>#var#</b><br></if>

  and so on.

- If you set '@collapse_whitespace' the processor will collapse all
  adjacent whitespace (including line terminators) to a single space.  An
  exception is made for markup appearing within <textarea>, <pre> and
  <quote> tags.  Similarly, setting '@collapse_blank_lines' (and not
  '@collapse_whitespace', which takes precedence), will cause adjacent line
  terminators to be collapsed to a single newline character.  We use the
  former for a final pass in order to produce efficient HTML, the latter
  for the preprocessor, to improve the readability of generated HTML with a
  lot of blank lines in it.

HTML::Macro is copyright (c) 2000,2001,2002 by Michael Sokolov and
Interactive Factory (sm).  Some rights may be reserved.  This program is
free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=head1 AUTHOR

Michael Sokolov, sokolov@ifactory.com

=head1 SEE ALSO HTML::Macro::Loop

perl(1).

=cut







