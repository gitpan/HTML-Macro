# HTML::Macro::Loop; Loop.pm
# Copyright (c) 2001,2002 Michael Sokolov and Interactive Factory. All rights
# reserved. This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package HTML::Macro::Loop;

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
$VERSION = '1.01';


# Preloaded methods go here.

sub new ($$$)
{
    my ($class, $page) = @_;
    my $self = {
        'vars' => [],
        'rows' => [],
        '@debug' => $page->{'@debug'} || 0,
        '@collapse_whitespace' => $page->{'@collapse_whitespace'},
        '@collapse_blank_lines' => $page->{'@collapse_blank_lines'},
        '@parent' => $page,
        '@incpath' => $page->{'@incpath'},
        '@precompile' => $page->{'@precompile'} || 0,
        };
    bless $self, $class;
    return $self;
}

sub declare ($@)
# use this to indicate which vars are expected in each iteration.
# Fills the vars array.
{
    my ($self, @vars) = @_;
    @ {$$self {'vars'}} = @vars;
}

sub push_array ($@)
# values must be pushed in the same order as they were declared, and all
# must be present
{
    my ($self, @vals) = @_;
    die "HTML::Macro::Loop::push_array: number of vals pushed(" . (@vals+0) . ") does not match number declared: " . (@ {$$self{'vars'}} + 0)
        if (@vals + 0 != @ {$$self{'vars'}});
    my $row = &new_row;
    my $i = 0;
    foreach my $var (@ {$$self{'vars'}})
    {
        $row->set ($var, $vals[$i++]);
    }
    push @ {$$self{'rows'}}, $row;
}

sub new_row
{
    my ($self) = @_;
    my $row = new HTML::Macro;
    $row->set ('@parent', $self);
    $row->{'@debug'} = $self->{'@debug'};
    $row->{'@collapse_whitespace'} = $self->{'@collapse_whitespace'};
    $row->{'@collapse_blank_lines'} = $self->{'@collapse_blank_lines'};
    $row->{'@incpath'} = $self->{'@incpath'};
    $row->{'@precompile'} = $self->{'@precompile'};
    return $row;
}

sub pushall_arrays ($@)
# values must be pushed in the same order as they were declared, and all
# must be present.  Arg is an array filled with refs to arrays for each row
{
    my ($self, @rows) = @_;
    foreach my $row (@rows) {
        $self->push_array (@$row);
    }
}

sub push_hash ($$)
# values passed with var labels so they may come in any order and some may be 
# absent (in which case zero is subtituted).  However, any values passed whose
# vars were not declared are -silently- ignored unless there has been no 
# declaration, in which case the keys of the hash are accepted as an implicit 
# declaration.
{
    my ($self, $pvals) = @_;
    my @ordered_vals;
    my $row = &new_row;
    $self->declare (keys %$pvals) if (!@ {$$self{'vars'}}) ;
    my $i = 0;
    foreach my $var (@ {$$self{'vars'}})
    {
        $row->set ($var, defined($$pvals{$var}) ? $$pvals{$var} : '');
    }
    push @ {$$self{'rows'}}, $row;;
}

sub set ($$$ )
# set a single value in the last row
{
    my ($self, $key, $val) = @_;
    if (! $$self{'rows'} )
    {
        $self->push_hash ({$key => $val});
    } else {
        my $rows = $$self{'rows'};
        my $row = $$rows[$#$rows];
        $row->set ($key, $val);
    }
}

sub doloop ($$ )
# perform repeated processing a-la HTML::Macro on the loop body $body,
# concatenate the results and return that.
{
    my ($self, $body) = @_;
    my $buf = '';
    foreach my $row (@ {$$self{'rows'}})
    {
        my $iteration;
        $buf .= $row->process_buf ($body);
    }
    return $buf;
}

sub new_loop ()
{
    my ($self, $name, @loop_vars) = @_;

    my $rows = $$self{'rows'};
    my $new_loop = new HTML::Macro::Loop ($$rows [$#$rows]);

    if ($name) {
        $self->set ($name, $new_loop);
    }
    if (@loop_vars) {
        $new_loop->declare (@loop_vars);
    }
    return $new_loop;
}

sub is_empty ()
{
    my ($self) = @_;
    return ! ($self->{'rows'} && (@ {$self->{'rows'}} > 0));
}

sub keys ()
{
    my ($self) = @_;
    return () if $self->is_empty();
    my $rows = $$self{'rows'};
    return ($$rows [$#$rows])->keys();
}

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

HTML::Macro::Loop - looping construct for repeated HTML blocks

=head1 SYNOPSIS

  use HTML::Macro;
  use HTML::Macro::Loop;
  $htm = HTML::Macro->new();
  $loop = $htm->new_loop('loop-body', 'id', 'name', 'phone');
  $loop->push_array (1, 'mike', '222-2389');
  $loop->push_hash ({ 'id' => 2, 'name' => 'lou', 'phone' => '111-2389'});
  $htm->print ('test.html');

=head1 DESCRIPTION

  HTML::Macro::Loop processes tags like 

<loop id="loop-tag"> loop body </loop>

    Each loop body is treated as a nested HTML::Macro within which variable
substitutions, conditions and nested loops are processed as described under
HTML::Macro.
    

    Each call to push_array and push_hash inserts a new loop iteration.
When the loop is evaluated these iterations are used (in the order they
were inserted) to create HTML::Macros that are applied to the loop body.
push_hash is analogous to HTML::Macro::set_hash; it sets up multiple variable
substitutions.  push_array must be used in conjunction with declare.
declare provides the list of keys that are implicitly associated with the
values in the corresponding positions in the argument list of push_array.

    An HTML::Macro::Loop object is associated with a loop tag by setting it to
the value of the loop tag in an HTML::Macro.  This has the effect that the
name spaces of page variables and loop tags overlap.

For example:

    $htm->set ('loop-tag', $loop);

Ordinarily, however, loops are created using the HTML::Macro::new_loop
function.  This first argument to new_loop is the loop tag; all subsequent
arguments are loop keys.  

Each iteration of the loop, created by calling push_arry or push_hash, sets
a value for each of the declared loop keys.  If keys are not declared
explicitly using new_loop, they may be declared implicitly by the first
call to push_hash.  The number of elements in the arrays passed to
push_array must match the number of declared loop keys.

HTML::Macro::Loop::pushall_arrays is a shortcut that allows a number of loop
iterations to be pushed at once.  It is typically used in conjunction with
DBI::selectall_arrayref.

Variable substitution within a loop follows the rule that loop keys take
precedence over "global" variables set by the enclosing page (or any outer
loop(s)).

is_empty returns a true value iff the loop has at least one row.

=head1 AUTHOR

Michael Sokolov, sokolov@ifactory.com

=head1 SEE ALSO HTML::Macro

perl(1).

=cut

