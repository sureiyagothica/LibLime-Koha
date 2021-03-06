#!/usr/bin/env perl

use Koha;
use C4::Context;
use C4::Output;
use C4::Auth qw(:DEFAULT get_session);
use C4::Search;
use C4::Biblio;  # GetBiblioData
use C4::Koha;
use C4::Languages qw(getAllLanguages);
use C4::Branch; # GetBranches
use C4::XSLT;
use MARC::Record;
use URI::Escape;
use Koha::Solr::Service;
use Koha::Solr::Query;
use Koha::Pager;


my $DisplayMultiPlaceHold = C4::Context->preference("DisplayMultiPlaceHold");
# create a new CGI object
# FIXME: no_undef_params needs to be tested
use CGI qw('-no_undef_params');
my $cgi = CGI->new();


my ($template,$borrowernumber,$cookie);

# decide which template to use
my $template_name;
my $search_form = 1;

if ( defined $cgi->param("q")) {
	$template_name = 'catalogue/results.tmpl';
    $search_form = 0;
} else {
    $template_name = 'catalogue/advsearch.tmpl';
}
# load the template
($template, $borrowernumber, $cookie) = get_template_and_user({
    template_name => $template_name,
    query => $cgi,
    type => "intranet",
    authnotrequired => 0,
    flagsrequired => { catalogue => 1 },
    }
);

my $last_borrower_show_button = 0;
if ( $cgi->cookie('last_borrower_borrowernumber') && $cgi->param('last_borrower_show_button') ) {
  $last_borrower_show_button = 1;
}
$template->param(
  last_borrower_show_button => $last_borrower_show_button,
  last_borrower_borrowernumber => $cgi->cookie('last_borrower_borrowernumber'),
  last_borrower_cardnumber => $cgi->cookie('last_borrower_cardnumber'),
  last_borrower_firstname => $cgi->cookie('last_borrower_firstname'),
  last_borrower_surname => $cgi->cookie('last_borrower_surname'),
);

# The following should only be loaded if we're bringing up the advanced search template
if ( $search_form ) {
    # load the branches
    my $mybranch = ( C4::Context->preference('SearchMyLibraryFirst') && C4::Context->userenv && C4::Context->userenv->{branch} ) ? C4::Context->userenv->{branch} : '';
    $template->param(
        branchloop              => GetBranchesLoop($mybranch, 0),
        searchdomainloop        => GetBranchCategories(undef,'searchdomain'),
        search_languages_loop   => getAllLanguages(),
        search_form             => 1,
    );
    my $itemtypes = GetItemTypes;
    my @itemtypesloop;
    my @ccodesloop;
    
    my $cnt = 0;
    my $advanced_search_types = C4::Context->preference('AdvancedSearchTypes');
    my @advanced_search_limits = (C4::Context->preference('AdvancedSearchLimits')) ? split(/\|/,C4::Context->preference('AdvancedSearchLimits')) : ();
    
    if ( grep(/ItemTypes/i,@advanced_search_limits) ) {
    	foreach my $thisitemtype ( sort {$itemtypes->{$a}->{'description'} cmp $itemtypes->{$b}->{'description'} } keys %$itemtypes ) {
            my %row =(  number=>$cnt++,
    				field => 'itemtype',
                    code => $thisitemtype,
                    description => $itemtypes->{$thisitemtype}->{'description'},
                    count5 => $cnt % 4,
                    imageurl=> getitemtypeimagelocation( 'intranet', $itemtypes->{$thisitemtype}->{'imageurl'} ),
                );
        	push @itemtypesloop, \%row;
    	}
        $template->param(itemtypeloop => \@itemtypesloop, ItemTypeLimit => 'ItemTypes');
    }
    if ( grep(/CCodes/i,@advanced_search_limits)  ) {
        $cnt = 0;
        my $advsearchtypes = GetAuthorisedValues('CCODE');
    	for my $thisitemtype (sort {$a->{'lib'} cmp $b->{'lib'}} @$advsearchtypes) {
    		my %row =(
    				number=>$cnt++,
                    field => 'collection',
                    code => $thisitemtype->{authorised_value},
                    description => $thisitemtype->{'lib'},
                    count5 => $cnt % 4,
                    imageurl=> getitemtypeimagelocation( 'intranet', $thisitemtype->{'imageurl'} ),
                );
            push @ccodesloop, \%row;
    	}
        $template->param(ccodeloop => \@ccodesloop, CCodeLimit => 'CCodes');
    }
    if ( grep(/ShelvingLocations/i,@advanced_search_limits)  ) {
        my @shelvinglocsloop;
        $cnt = 0;
        my $shelflocations =GetAuthorisedValues("LOC");
        for my $thisloc (sort {$a->{'lib'} cmp $b->{'lib'}} @$shelflocations) {
            my %row =(
                    number => $cnt++,
                    field => 'location',
                    code => $thisloc->{authorised_value},
                    description => $thisloc->{'lib'},
                    count5 => $cnt % 4,
                  );
            push @shelvinglocsloop, \%row;
        }
        $template->param(shelvinglocsloop => \@shelvinglocsloop,ShelvingLocationLimit => 'ShelvingLocations');
    }

    {
        use Koha::Format;
        my %cat_desc = Koha::Format->new->all_descriptions_by_category;
        my @formatsloop;
        for ( qw(print video audio computing other) ) {
            push @formatsloop,
                { labels =>
                      [ map {{description=>$_}} @{$cat_desc{$_}} ]
                };
        }
        $template->param( formatsloop => \@formatsloop);
    }

    $template->param(DateRangeLimit => 'DateRange') if grep(/DateRange/i,@advanced_search_limits);
    $template->param(SubtypeLimit => 'Subtypes') if grep(/Subtypes/i,@advanced_search_limits);
    $template->param(LanguageLimit => 'Language') if grep(/Language/i,@advanced_search_limits);
    $template->param(LocationLimit => 'LocationAvailability') if grep(/LocationAvailability/i,@advanced_search_limits);
    $template->param(SortByLimit => 'SortBy') if grep(/SortBy/i,@advanced_search_limits);

    # set the default sorting
    if (C4::Context->preference('defaultSortField') && C4::Context->preference('defaultSortOrder')){
        my $default_sort_by = C4::Context->preference('defaultSortField')."_".C4::Context->preference('defaultSortOrder') ;
        $template->param($default_sort_by => 1);
    }

    my $expand_options = C4::Context->preference("expandedSearchOption");
    my $search_boxes_count = C4::Context->preference("OPACAdvSearchInputCount") || 3;  # FIXME: using OPAC sysprefs?
    my @search_boxes_array = map({}, (1..$search_boxes_count)); # HTML::Template needs a hashref.
    $template->param( advsearch => 1,
                      search_boxes_loop => \@search_boxes_array,
                      #search_boxes_loop => [1..$search_boxes_count],
                      expanded_options => $expand_options, );

    output_html_with_http_headers $cgi, $cookie, $template->output;
    exit;
}

### If we're this far, we're performing an actual search



## DO THE SEARCH AND GET THE RESULTS
my $total = 0; # the total results for the whole set
my $facets; # this object stores the faceted results that display on the left-hand of the results page

my $solr = new Koha::Solr::Service;

my $solr_query = Koha::Solr::Query->new({cgi => $cgi, rtype => 'bib'});

if($solr_query->simple_query){
    my $q = $solr_query->simple_query();
    my $idx = $solr_query->simple_query_field();
    if ( $idx ) {
        $q =~ s/^\(|\)$//g;
    }
    $template->param( ms_query => $q, ms_idx => $idx );
}

my $rs = $solr->search($solr_query->query,$solr_query->options);

if(!$rs->is_error){

    my $results = $rs->content;
    if($results->{spellcheck}->{suggestions}){
        my %spell = ();
        for(my $i = 0; $i<@{$results->{spellcheck}->{suggestions}}; $i=$i+2){
            # suggestions come back as array, first individual terms, then collations.
            # for now, we ignore the terms and just use collations.
            next unless $results->{spellcheck}->{suggestions}[$i] ~~ 'collation';
            $spell{$results->{spellcheck}->{suggestions}[$i+1]->[1]} = $results->{spellcheck}->{suggestions}[$i+1]->[3];
            # i.e. collationQuery => hits  // would be safer to read the array into a hash, but this will probably change before long.
        }
        my $suggest_cnt = C4::Context->preference('StaffSearchSuggestionsCount');
        my @didyoumean = map { term => $_ }, sort { $spell{$b} <=> $spell{$a} } keys(%spell);
        @didyoumean = @didyoumean[0 .. $suggest_cnt-1] if(scalar(@didyoumean)>$suggest_cnt);
 
        $template->param( didyoumean => \@didyoumean );
    }

    my $hits = $results->{'response'}->{'numFound'};
    my $maxscore = $results->{'response'}->{'maxScore'};
    
    $template->param( 'user_query' => $solr_query->query,
                      'user_limit' => $solr_query->limits,  # Note this is an arrayref, not a string.
                      'user_sort' => $solr_query->options->{'sort'},
                      'query_uri'  => $solr_query->uri,
                      'solr_fq'    => join(' ', @{$solr_query->options->{'fq'}}),
            );

    my @newresults = ();
    my $offset = $results->{'response'}->{'start'};
    my $i = 0;
    for my $doc (@{$results->{response}->{docs}}){
        $i++;
        my $bib = C4::Search::searchResultDisplay($doc);
        $bib->{result_number} = $offset + $i;
        push @newresults, $bib;
    }

    ## If there's just one result, redirect to the detail page # TODO: Merge marcdetail and isbddetail into detail
    if ($hits == 1) {         
        my $defaultview = C4::Context->preference('IntranetBiblioDefaultView');
        my $views = { C4::Search::enabled_staff_search_views }; 
        my $biblionumber = $newresults[0]->{biblionumber};
        if ($defaultview eq 'isbd' && $views->{can_view_ISBD}) {
            print $cgi->redirect("/cgi-bin/koha/catalogue/ISBDdetail.pl?biblionumber=$biblionumber");
        } elsif  ($defaultview eq 'marc' && $views->{can_view_MARC}) {
            print $cgi->redirect("/cgi-bin/koha/catalogue/MARCdetail.pl?biblionumber=$biblionumber");
        } elsif  ($defaultview eq 'labeled_marc' && $views->{can_view_labeledMARC}) {
            print $cgi->redirect("/cgi-bin/koha/catalogue/labeledMARCdetail.pl?biblionumber=$biblionumber");
        } else {
           # warp to item view for a barcode
           if ($solr_query->looks_like_barcode) {
              my @inums = split(/\s*\|\s*/,$newresults[0]->{itemnumber});
              my @bc    = split(/\s*\|\s*/,$newresults[0]->{barcode});
              my $itemnumber;
              for my $i(0..$#bc) {
                 if ($solr_query->looks_like_barcode() == $bc[$i]) {
                    $itemnumber = $inums[$i];
                    print $cgi->redirect('/cgi-bin/koha/catalogue/moredetail.pl'
                    ."?biblionumber=$biblionumber"
                    ."#item$itemnumber");
                    exit;
                 }
              }
           }
           print $cgi->redirect("/cgi-bin/koha/catalogue/detail.pl?q="
           . $solr_query->query . "&biblionumber=$biblionumber&last_borrower_show_button=$last_borrower_show_button");
        } 
    } elsif ($hits) {
        my $pager = Koha::Pager->new({pageset => $rs->pageset});
        if($last_borrower_show_button){
            $pager->extra_param("last_borrower_show_button=1");
        }
        $template->param(total => $hits,
                        DisplayMultiPlaceHold => C4::Context->preference("DisplayMultiPlaceHold"),
                        searchdesc => 1,
                        SEARCH_RESULTS => \@newresults,
                        facets_loop => $rs->koha_facets(),
                        last_query => $solr_query->query(),
                        offset => $offset,  # for rss
                        pager => Koha::Pager->new({pageset => $rs->pageset})->tmpl_loop(),
                        );
    } else {
        # no hits
        # Offer a fuzzy search, perhaps.
        $template->param(total => $hits,
                        searchdesc => 1,
                        last_query => $solr_query->query(),
                        );
    }
    $template->param( z3950_param => $solr_query->z3950_uri_param );

} else {
    $template->param( query_error => 1);
    #warn p $rs->raw_response;
}

output_html_with_http_headers($cgi, $cookie, $template->output);

