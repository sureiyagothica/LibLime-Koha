#!/usr/bin/env perl

#script to place reserves/requests
#writen 2/1/00 by chris@katipo.oc.nz


# Copyright 2000-2002 Katipo Communications
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA

use strict;
use warnings;
use C4::Biblio;
use C4::Items;
use CGI;
use C4::Output;
use C4::Reserves;
use C4::Circulation;
use C4::Members;
use C4::Auth;

my $input = CGI->new();

my ( undef, undef, undef) = get_template_and_user(
    {
        template_name   => "reserve/request.tmpl",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { reserveforothers => '*' },
    }
);

my @bibitems=$input->param('biblioitem');
my $biblionumber=$input->param('biblionumber');
my $borrower=$input->param('member');
my $notes=$input->param('notes');
my $branch=$input->param('pickup');
my $startdate=$input->param('reserve_date') || '';
my @rank=$input->param('rank_request');
my $type=$input->param('type');
my $title=$input->param('title');
my $borrowernumber=GetMember($borrower,'cardnumber');
my $checkitem=$input->param('checkitem');

my $multi_hold = $input->param('multi_hold');
my $biblionumbers = $multi_hold ? $input->param('biblionumbers') : ($biblionumber . '/');
my $bad_bibs = $input->param('bad_bibs');

my %bibinfos = ();
my @biblionumbers = split '/', $biblionumbers;
foreach my $bibnum (@biblionumbers) {
    my %bibinfo = ();
    $bibinfo{title} = $input->param("title_$bibnum");
    $bibinfo{rank} = $input->param("rank_$bibnum");
    $bibinfos{$bibnum} = \%bibinfo;
}

my $found;

# if we have an item selectionned, and the pickup branch is the same as the holdingbranch
# of the document, we force the value $rank and $found .
## UPDATE: syspref is broken in the OFF state due to branchtransfers destbranch same as holdingbranch
## without item arrived; will not work in consortium
#if ($checkitem && $checkitem ne ''){
#    $rank[0] = '0' unless C4::Context->preference('ReservesNeedReturns');
#    my $item = $checkitem;
#    $item = GetItem($item);
#    if ( $item->{'holdingbranch'} eq $branch ){
#        $found = 'W' unless C4::Context->preference('ReservesNeedReturns');
#    }
#}

if ($type eq 'str8' && $borrowernumber ne ''){

    foreach my $biblionumber (keys %bibinfos) {
        my $count=@bibitems;
        @bibitems=sort @bibitems;
        my $i2=1;
        my @realbi;
        $realbi[0]=$bibitems[0];
        for (my $i=1;$i<$count;$i++) {
            my $i3=$i2-1;
            if ($realbi[$i3] ne $bibitems[$i]) {
                $realbi[$i2]=$bibitems[$i];
                $i2++;
            }
        }
        my $const;

        if ($multi_hold) {
            my $bibinfo = $bibinfos{$biblionumber};
            AddReserve($branch,$borrowernumber->{'borrowernumber'},$biblionumber,'a',[$biblionumber],
                       $bibinfo->{rank},$startdate,$notes,$bibinfo->{title},$checkitem,$found);
        } else {
            AddReserve($branch,$borrowernumber->{'borrowernumber'},$biblionumber,'a',\@realbi,$rank[0],$startdate,$notes,$title,$checkitem,$found);
        }
    }

    my $url;
    if ($multi_hold) {
        $url = "/cgi-bin/koha/members/moremember.pl?borrowernumber=$borrowernumber->{borrowernumber}"
    }
    else {
        my $searchtohold = $input->param('searchtohold');
        $url = "editholds.pl?searchtohold=$searchtohold&close_greybox=$searchtohold&biblionumber=$biblionumber&sortRev=ASC";
    }
    print $input->redirect($url);
   exit;
} elsif ($borrowernumber eq ''){
	print $input->header();
	print "Invalid card number please try again";
	print $input->Dump;
}
exit;
__END__
