#!/usr/bin/perl -w

#
# Copyright (c) 2003-2006 University of Chicago and Fellowship
# for Interpretations of Genomes. All Rights Reserved.
#
# This file is part of the SEED Toolkit.
#
# The SEED Toolkit is free software. You can redistribute
# it and/or modify it under the terms of the SEED Toolkit
# Public License.
#
# You should have received a copy of the SEED Toolkit Public License
# along with this program; if not write to the University of Chicago
# at info@ci.uchicago.edu or the Fellowship for Interpretation of
# Genomes at veronika@thefig.info or download a copy from
# http://www.theseed.org/LICENSE.TXT.
#

package TargetCriterionGeneric;

    use strict;
    use Tracer;
    use Sprout;
    use base qw(TargetCriterionQuery);

=head1 Generic Match Target Search Criterion Object

=head2 Introduction

This is a search criterion object for search criteria involving a match against a
single database text field. The user inputs a string that is to be matched either to
a substring of the text field or a prefix of the text field. Unlike a normal query-based
search, the sanity of this one is specified in the constructor.

This object uses the followng additional object fields.

=over

=item infix

Style of match: C<exact> for an exact match, C<prefix> if only the prefix of the field
needs to match, or C<scan> if any substring of the field can match.

=item sanity

TRUE if this search should be considered sane, else FALSE.

=back

=head2 Special Methods

=head3 new

    my $tc = TargetCriterionGeneric->new($rhelp, $name, $label, $hint, $infix, $field => @path);

Construct a new TargetCriterionGeneric object. The following parameters are
expected.

=over 4

=item rhelp

[[ResultHelperPm]] object for the active search.

=item name

Identifying name of this criterion.

=item label

Label to display for this criterion in the type dropdown.

=item hint

The hint tooltip to be displayed for this criterion.

=item infix

Style of match: C<exact> for an exact match, C<prefix> if only the prefix of the field
needs to match, or C<scan> if any substring of the field can match.

=item sanity

TRUE if this search should be considered sane, else FALSE.

=item field

Name of the database field containing the code value.

=item path

List of object names, indicating the path from the Feature or Genome table to the
table containing the code value. The first object will be C<Feature> for a feature-based
criterion and C<Genome> for a genome-based one. Frequently, the path will stop with
the first object. When this happens, the criterion can be processed very efficiently.

=back

=cut

sub new {
    # Get the parameters.
    my ($class, $rhelp, $name, $label, $hint, $infix, $sanity, $field, @path) = @_;
    # Construct the underlying object.
    my $retVal = TargetCriterionQuery::new($class, $rhelp, { label => $label,
                                                            hint => $hint,
                                                            text => 1,
                                                            name => $name },
                                           $field, @path);
    # Remember the local flags.
    $retVal->{infix} = $infix;
    $retVal->{sanity} = $sanity;
    # Return the object.
    return $retVal;
}

=head2 Virtual Methods

=head3 Validate

    my $okFlag = $tc->Validate($parms);

Return TRUE if the specified parameters are valid for a search criterion of this type
and FALSE otherwise. If an error is detected, the error message can be retrieved using
the L</message> method.

=over 4

=item parms

A Criterion Parameter Object whose fields are to be validated.

=item RETURN

Returns TRUE if the parameters are valid, else FALSE.

=back

=cut

sub Validate {
    # Get the parameters.
    my ($self, $parms) = @_;
    # Default to valid.
    my $retVal = 1;
    # Get the string value.
    my $value = $parms->{stringValue};
    # It's only invalid if it's blank.
    if (! defined $value || $value eq '' || $value =~ /^\s+$/) {
        $retVal = 0;
        $self->SetMessage("No value specified for $self->{label}.");
    }
    # Return the validation code.
    return $retVal;
}

=head3 ComputeQuery

    my ($joins, $filterString, $parms) = $tc->ComputeQuery($criterion);

Compute the SQL filter, join list, and parameter list for this
criterion. If the criterion cannot be processed by SQL, then nothing is
returned, and the criterion must be handled during post-processing.

The join list and the parameter list should both be list references. The
filter string is a true string.

If the filter string only uses the B<Genome> and B<Feature> tables, then the
join list can be left empty. Otherwise, the join list should start with the
particular starting point (B<Genome> or B<Feature>) and list the path through
the other relevant entities and relationships. Each criterion will have its
own separate join path. 

=over 4

=item criterion

Reference to a Criterion Parameter Object.

=item RETURN

Returns a 3-tuple consisting of the join list, the relevant filter string,
and the matching parameters. If the criterion cannot be processed using
SQL, then the return list contains three undefined values. (This is what happens if
you don't override this method.)

=back

=cut

sub ComputeQuery {
    # Get the parameters.
    my ($self, $criterion) = @_;
    # Get the name of the relevant field with the appropriate suffix.
    my $fieldName = $self->RelevantField($criterion->{idx});
    # Compute the join list.
    my $joins = $self->JoinList();
    # Compute the filter string.
    my $filterString = "$fieldName LIKE ?";
    # Get the parameter value.
    my $parm = $criterion->{stringValue};
    # Add the vild cards.
    my $infix = $self->{infix};
    if ($infix eq 'scan') {
        $parm = "%$parm%";
    } elsif ($infix eq 'prefix') {
        $parm .= "%";
    }
    # Return the results.
    return ($joins, $filterString, [$parm]);
}

=head3 CheckValue

    my $match = $tc->CheckValue($criterion, $valueData);

Return TRUE if the current feature matches this criterion, else FALSE.

=over 4

=item criterion

Criterion Parameter object describing this criterion's parameters.

=item valueData

Value computed for the current feature by the L</GetValueData> method.

=item RETURN

Returns TRUE if the current feature matches the criterion, else FALSE.

=back

=cut

sub CheckValue {
    # Get the parameters.
    my ($self, $criterion, $valueData) = @_;
    # Get the criterion value to compare against it. We fold to lower case because
    # we're using the case-insensitive LIKE in the SQL.
    my $comparator = lc $criterion->{stringValue};
    # Get the comparison type.
    my $infix = $self->{infix};
    # Declare the return value.
    my $retVal;
    # Look for the comparator value in the field. Note that the process is case-insensitive,
    # because this is an SQL "LIKE" operation. Also, we exit the loop immediately if we
    # have a match.
    for my $value (@$valueData) { last if $retVal;
        my $lcValue = lc $value;
        if ($infix eq 'exact') {
            $retVal = ($lcValue eq $comparator);
        } else {
            my $found = index($comparator, $lcValue);
            if ($infix eq 'prefix') {
                $retVal = ($found == 0);
            } else {
                $retVal = ($found > 0);
            }
        }
    }
    # Return the result.
    return $retVal;
}

=head3 Sane

    my $flag = $tc->Sane($parms);

Return TRUE if this is a sane criterion, else FALSE. Every search must have at least one
sane criterion in order to be valid.

=over 4

=item parms (optional)

A Criterion Parameter Object for the current query.

=item RETURN

Returns TRUE if this query returns a relatively limited result set and uses SQL,
else FALSE. If you do not override this method, it returns FALSE.

=back

=cut

sub Sane {
    my ($self) = @_;
    return $self->{sanity};
}

1;
