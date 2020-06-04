#!/usr/bin/perl
# -*- coding: utf-8 -*-

use strict;
use warnings;

use IPC::System::Simple qw( system );
use Getopt::Long;
use JSON::Parse 'json_file_to_perl';
use WWW::Mechanize;
use LWP::Simple;	#implement get() subroutine
use Pod::Usage qw(pod2usage);

use utf8;	# tell perl to match regex in unicode
use open qw/:std :encoding(UTF-8)/; # Tell perl that STDOUT etc. should be UTF-8 encoded

use File::Basename qw(dirname fileparse);
use Cwd qw(abs_path);
use lib dirname( abs_path $0 ) . '/lib';    	# $0 = name of the current script
												# abs_path() returns the abs_path of this script
												# dirname() return the directory part of a file (its location)
use My::MyToken qw(MyToken);



sub TTline2MyToken { 
	#Convert a TreeTagger line into an instance of MyToken

	my $line = $_[0];
	chomp( $line );

	my @TTToken = split( /\t/, $line );
	my $token = new MyToken( @TTToken );

	return $token;
}


sub tScore {
	#Compute t-score of an ngram based on the output format of count.pl (NSP)

	my $nbr_ngrams = $_[0];
	my $line = $_[1];

	my @ngram = split( /<>/, $line );
	my $freq = $ngram[-1];

	  #( freq of the whole ngram, freq of the first word, freq of the sec word )
	my ( $freq_ngram, $freq_a, $freq_b ) = split( / /, $freq ); 

	 # expected frequency of the ngram, knowing the freq of each word
	my $freq_ngram_exp = $freq_a * $freq_b / $nbr_ngrams;
	my $tscore = ( $freq_ngram - $freq_ngram_exp ) / sqrt($freq_ngram);

	return $tscore;

}


#Initializing most of the variables
my $config = json_file_to_perl( "./config/config.json" );
my $path = $config->{"root_path"};
my $language = $config->{"language"};
my $stop_words = $config->{"stop_words"};
my $n = $config->{"n"};
my $tokenizer = "./config/1TokenPerLine.tokenizer";	#the tokenizer should not be modified since
													#the tokenisation is made by TreeTagger
my $sort = $config->{"sort"};
my $method = $config->{"method"};
my $search;
my $man = 0;
my $help = 0;


#Parsing the options
GetOptions( 'help|?'	=> \$help
	      , 'man'		=> \$man
		  , 'input=s' 	=> \my $input_file_path
		  , 'language:s' => \$language
		  , 'sort:s' 	=> \$sort #frequency or t-score
		  , 'method|m:s'	=> \$method #token, tag, lemma or all
		  , 'n:i'		=> \$n #number of results (coll) of elements of the context (conc) to print
		  , 'pattern:s' => \my $pattern_str
		  , 'search|s=s'	=> \$search #coll, conc
		  , 'demo:s'	=> \my $demo
		  );
if ( $demo ) {
	$search = "coll";
	$method = "lemma";

	if ($demo =~ "fr") {
		$language = "french";
	}
	elsif ( $demo =~ "en" ) {
		$language = "english";
	}
	else {
		die ( "\nThe language $demo is not supported for the demo. Only 'en' and 'fr' are supported\n" );
	}
}


#opening man or help
pod2usage({-verbose => 1, -exitval => 0})
	if $help;	#print SYNOPSIS and ARGUMENTS
pod2usage({-verbose => 2, -exitval => 0})
	if $man;


#defining input/output paths
my $full_time = localtime();
my ($week_day, $month, $day, $hour, $year) = split( " ", $full_time );
my $wikifile_path = "$path/demo/$language$year$month$day.wiki";
$input_file_path = $wikifile_path if ( $demo );
my($filename, $directories, $suffix) = fileparse($input_file_path, qr/\.[^.]*/);
my $tagfile_path = "$path/corpora/$filename.tag";
my $nspfile_path = "$path/corpora/$filename.nsp";
my $concfile_path = "$path/corpora/$filename.conc";
my $tmpfile_path = "$path/corpora/tmp";	#temporary file that applies the method asked by the user
my $ngramfile_path = "$path/corpora/$filename.ngram";


#Several exit conditions
die("'root_path' points to an unexisting directory. Please modify it in the file ./config/config.json.\n")
	if ( not -d "$path/" );
die ( "\nNo input file provided. 'perl collExtractor.pl --man' for more info\n" ) 
	if ( not $input_file_path and not $demo );
die ("\nInvalid input file path. 'perl collExtractor.pl --man' for more info\n" ) 
	if (not -e $input_file_path and not $demo );
die ( "\nConcordancer method with no pattern. 'perl collExtractor.pl --man' for more info\n" ) 
	if ( $search eq "conc" and not $pattern_str );
die ( "\n--pattern (-p) option cannot be used with --search=coll. 'perl collExtractor.pl --man' for more info\n" )
	if ( $search eq "coll" and $pattern_str );


#defining tree-tagger language
my $TT;
$TT = "tree-tagger-$language";
$TT = "tree-tagger-french" if ( ( lc($language) eq "fr" ) or ( lc($language) eq "français" ) );
$TT = "tree-tagger-english" if ( ( lc($language) eq "en" ) or ( lc($language) eq "english" ) );


sub getParagraphs {
	#return the text written in html paragraphs

	my $html = $_[0];
	my $text = "";
	while ( $html =~ /<p>(.+?\n)<\/p>/g ) {	#get the text from paragraphs
		$text .= $1;
	}
	$text =~ s/<.+?>//g;	#remove html elements
	$text =~ s/&#160;/ /g;	#replace inseparable space with white space
	return $text;
}


sub fetchLinks {
	#Get recursively the links of a Wikipedia page and prints the text (from paragraphs) into a file
	
	#arguments
	my $link = $_[0];
	my $text = $_[1];
	my $file = $_[2];
	my $rec_depth = $_[3];

	#getting the text from current page
	my $mech = WWW::Mechanize->new();

	my $page_html = get( $link );
	my $paragraphs = getParagraphs( $page_html );
	print $file "$paragraphs\n";

	#Base case
	return if ($rec_depth < 1 );

	#recursion
	my $page = $mech->get( $link );
	my @links = $mech->links();
	foreach my $link ( @links ) {
		my $link_text = $link->url();
		#filter "useless" wiki pages
		if ( $link_text =~ /^\/wiki\/[^:.]*$/ ) {
			$link = $link->url_abs();
			fetchLinks( $link, $text, $file, $rec_depth-1 );
		}
	}
	return;
}


#Demo
if ($demo) {
	print STDERR "This demo will download texts from Wikipedia in the language asked, and will list all its bigrams based on lemmas (not tokens!), sorted by frequency. The whole list will be printed into a file. The best results will also be printed on the screen, along with their frequency and their t-score.\n\n";

	#Fettching wiki pages
	print STDERR "Fetching Wikipedia pages... This can take a few minutes.\n";
	open( my $wikifile, ">", $wikifile_path);
	my $wiki_corpus = fetchLinks( "https://$demo.wikipedia.org/wiki/Main_Page", "", $wikifile, 1 ); #|| die("Could not access Wikipedia.");
	close( $wikifile );
	print STDERR "Fetching Wikipedia pages ok. (The downloaded corpus can be found in ./demo/$language$year$month$day.wiki).\n\n";

}


#tokenisation + tagging
print STDERR "\nTagging in progress...\n";
my $command = "$TT $input_file_path 2> /dev/null > $tagfile_path";
system("$command");
print STDERR "Tagging ok. (The tagged text can be found in ./corpora/$filename.tag)\n\n";


#Finding collocations
if ( $search =~ /coll/ ) {

	#filter according to chosen method
	if ( $method eq "all" ) {
		$tmpfile_path = $tagfile_path; #no modification needs to be made on the TT file
	}
	else {
		open ( my $tagfile, "<", $tagfile_path );
		open ( my $tmpfile, ">", $tmpfile_path );
		while ( my $line = <$tagfile> ) {
			chomp($line);
			my $my_token = TTline2MyToken($line);

			if ( $method eq "token" ) {
				print $tmpfile "$my_token->{token}\n";
			}
			elsif ( $method eq "tag" ) {
				print $tmpfile "$my_token->{tag}\n";
			}
			elsif ( $method eq "lemma" ) {
				print $tmpfile "$my_token->{lemma}\n";
			}
			else {
				die ("\nThe --method (-m) argument is not valid. 'perl collExtractor.pl --man' for more info.\n")
			}
		}
		close ( $tagfile );
		close ( $tmpfile );
	}

	# counting collocates frequency
	print STDERR "Counting in progress...\n";
	$command = "count.pl --token $tokenizer --stop $stop_words $nspfile_path $tmpfile_path";
	system( $command );
	print STDERR "Counting ok.\n\n";

	if ( $method ne "all" ) { # otherwise, tmp_path was equal to tagfile_path, and we don't want to delete it
			unlink $tmpfile_path;  	  # delete tmp file
	}


	#Getting t-score
	print STDERR "Calculating t-score...\n";
	my %res;
	my $res = \%res;
	open( my $nspfile, "<", $nspfile_path );
	my $nbr_ngrams = <$nspfile>; #the first line contains the total number of ngrams
		while ( my $line = <$nspfile> ) {
			chomp($line);
			my $tscore = tScore($nbr_ngrams, $line);
			$line =~ /(.+)<>([0-9]+) [0-9 ]+$/;
			my $ngram = $1;
			my $freq = $2;
			$res{$ngram}{"freq"} = $freq;
			$res{$ngram}{"tscore"} = $tscore;
		}
	close( $nspfile );
	unlink $nspfile_path;
	print STDERR "T-score calculated.\n\n";


	#Sorting n-grams
	print STDERR "Sorting the ngrams...\n";
	my @ordered_ngrams = ();

	if ( $sort =~ /freq/ ) {
		@ordered_ngrams = sort { $res->{$b}{"freq"} <=> $res->{$a}{"freq"} } keys %$res;
	}
	elsif ( $sort =~ /t/ ) {
		@ordered_ngrams = sort { $res->{$b}{"tscore"} <=> $res->{$a}{"tscore"} } keys %$res;
	}
	else {
		die "\nThe --sort (-s) option is not valid. 'perl collExtractor.pl --man' for more info\n";
	}


	#printing sorted ngrams into a file
	open( my $ngramfile, ">", $ngramfile_path );
	foreach my $ngram ( @ordered_ngrams ) {
		print $ngramfile "$ngram\t$res{$ngram}{'freq'}\t$res{$ngram}{'tscore'}\n";
	}
	close( $ngramfile );
	print STDERR "Sorting ok.\n\n";


	#Printing the n best results
	print STDERR "\n$n best results : \n";
	open( $ngramfile, "<", $ngramfile_path );
	for ( my $i = 0 ; $i < $n ; $i += 1 ) {
		my $line = <$ngramfile>;
		print STDOUT $line;
	}
	close( $ngramfile );
		print STDERR "\nThe full list of ngrams can be found in ./corpora/$filename.ngram\n";
}



#Concordancer
elsif ( $search =~ /conc/ ) {
	print STDERR "Finding concordances...\n";

	my $nbr_conc = 0;
	my $all_conc = "";
	my @pattern = ();
	my $joiner = "";

	#Splitting the arguments according to the method
	if ( $method eq "token" || $method eq "tag" || $method eq "lemma" ) {
		@pattern = split( / /, $pattern_str );
		$joiner = " ";
	}

	elsif ( $method eq "all" ) {
		@pattern = split( /<>/, $pattern_str );
		$joiner = $config->{joiner_whole_token};
	}

	else {
		die "\nThe --method (-m) option is not valid. 'perl collExtractor.pl --man' for more info\n";
	}

	my $len_pattern = @pattern;

	#Finding the concordances
	my @tokenArray = ();
	my $match = "";

	open( my $tagfile, "<", $tagfile_path);
	while ( my $line = <$tagfile> ) {
		chomp( $line );
		my $myToken = TTline2MyToken( $line );

		#add myToken in tokenArray, and remove the first elem if array bigger than the wanted concordance length
		push( @tokenArray, $myToken->{$method} );
		my $lenTokenArray = @tokenArray;
		shift( @tokenArray ) if ( $lenTokenArray > $n + 2);

		#beggining of match found
		if ( $myToken->{$method} eq $pattern[0] ) {

			#we go on reading the file while the match goes on
			my $continue = 1;
			for ( my $i = 1; $i < $len_pattern; $i += 1 ) {	
				$line = <$tagfile>;
				chomp($line);
				$myToken = TTline2MyToken( $line );
				push( @tokenArray, $myToken->{$method} );
				if ( $myToken->{$method} ne $pattern[$i]) {	#not full match
					$continue = 0;
				}
			}

			#match complete, looking for left and right context
			if ( $continue ) {

				$nbr_conc += 1;

				#left context + node
				my $lenTokenArray = @tokenArray;
				my $first_word_left = $lenTokenArray-$len_pattern-$n;
				$first_word_left = 0 if $first_word_left < 0;
				my @left_context = @tokenArray[$first_word_left..$lenTokenArray-1];
				$match = join( $joiner, @left_context );

				#right context
				my @right_context = ();
				for ( my $i = 0; $i < $n; $i += 1 ) {
					if ( defined( $line = <$tagfile> ) )  {	#return false if EOF reached
						chomp($line);
						$myToken = TTline2MyToken( $line );
						push( @right_context, $myToken->{$method} );
					}
				}

				$match .= $joiner;
				$match .= join( $joiner, @right_context );
				$all_conc .= "$match\n\n";
			}
		}
	}
	close( $tagfile );

	#Writing the result in a file
	open( my $concfile, ">", $concfile_path );
	print $concfile "$nbr_conc\n";
	print $concfile "$all_conc";
	close( $concfile );

	#printing 3 results on the screen
	open( $concfile, "<", $concfile_path );
	my $nbr_res = <$concfile>;	#the first line contains the number of results
	chomp ($nbr_res);
	print STDERR "$nbr_res concordances were found.";
	print STDERR " Here are some of them :\n\n" if ( ( $method eq "all" and $joiner eq "\n") or ( $method ne "all" ) );

	my $i_max;
	if ( $nbr_res >= 3 ) {
		$i_max = 3;
	}
	else {
		$i_max = $nbr_res;
	}

	for ( my $i = 0; $i < $i_max; $i += 1 ) {
		if ( $method eq "all") {
			if ( $joiner eq "\n" ) {
			my $line = <$concfile>;
				while ( $line =~ /.+\n/ ) {
					print STDOUT $line;
					$line = <$concfile>;
				}
				print STDOUT "\n";
			}
		#if $joiner ne "\n" -> nothing is printed because the format is unknown
		}
		else {
			my $line = <$concfile>;
			print STDOUT $line;
			$line = <$concfile>; #empty line
			print "\n"
		}
	}
	close( $concfile );

	print STDERR "\n(The full list of concordances can be found in ./corpora/$filename.conc)\n\n";

}


else {
	die "\nThe --search (-s) option is not valid. 'perl collExtractor.pl --man' for more info\n";
}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

CollExtractor - Extractor of collocations (token, lemma and/or tag) from input text, and concordancer.

=head1 VERSION

version 1.0
June 2020

=head1 SYNOPSIS

perl collExtractor.pl --search coll [options] --input FILE

perl collExtractor.pl --search conc [options] --pattern PATTERN --input FILE

perl collExtractor.pl --demo LANG

=head1 OPTIONS

=head2 GENERAL OPTIONS

=over 4

=item B<--help, -h ?>

Print Synopsis and Options parts of the manual and exit

=item B<--man>

Print the full manual

=item B<--input, -i> I<PATH>

Path (absolute or relative to the root of the program) to a text file (utf-8)

=item B<--search, -s coll|conc>

"coll" or "collocation" to find collocations;

"conc" or "concordances"to find the concordances of a pattern (see --pattern)

=item B<--language, -l> I<LANGUAGE>

Language that should be used by TreeTagger. Write it exactly as is written in the tree-tagger commands e.g. "english" for "tree-tagger-english"

=item B<--method, -m token|tag|lemma|all>

Defines on what element(s) the search will be conducted. Tokens are case sensitive. Lemmas must be written in lower case.

=back

=head2 OPTIONS SPECIFIC TO THE COLLOCATION EXTRACTOR

=over 4

=item B<--sort freq|t>

"freq" or "frequency" will write the result in reverse order of frequency ;

"t" will write the result in reverse order of t-score

=item B<-n INT>

If --search=coll, number of results that should be printed in the terminal.

If --search=conc, number of "words" that should be taken into account to the right and left of the node.

=back

=head2 OPTIONS SPECIFIC TO THE CONCORDANCER

=over 4

=item B<--pattern> I<PATTERN>

Pattern for which the concordances should be found. If several words are used, they should be written into quotes.

If --method=all, each "word" should be written as in the TreeTagger output i.e. "token tag lemma" (note the space between the elements, not before, not after) ; each "word" should be seperated by "<>".

To know what tagging taxonomy you should use, refer to the documentation of the version of TreeTagger you are using.

Example: --pattern "in PRP in<>a AT0 a<>certain AJ0 certain"

=item B<-n INT>

If --search=conc, number of "words" that should be taken into account to the right and left of the node.

If --search=coll, number of results that should be printed in the terminal.

=back

=head2 OTHER OPTION

=over 4

=item B<--demo, -d fr|en>

Activate the demo mode. It downloads texts from Wikipedia in the language asked, and will list all its bigrams based on lemmas (not tokens!), sorted by frequency. The whole list will be printed into a file. The best results will also be printed on the screen, along with their frequency and their t-score.

=back

=head1 EXAMPLES

perl collExtractor.pl --demo fr

perl collExtractor.pl --search coll --sort freq --method all -l en --input ./demo/english2020Jun3.wiki

perl collExtractor.pl -s coll --sort t -m lemma -l fr -i ./demo/french2020Jun3.wiki

perl collExtractor.pl --search conc --method token --pattern ". Il" -l fr --input ./demo/french2020Jun3.wiki

perl collExtractor.pl --s conc -m lemma -p ". il" --input ./demo/french2020Jun3.wiki -l fr

perl collExtractor.pl --s conc -m all -p ". SENT .<>Il PRO:PER il" -l fr --input ./demo/french2020Jun3.wiki

=head1 DESCRIPTION

B<collExtractor> implements an ngram extractor and a concordancer. The input text is tagged with TreeTagger. Ngram can be extracted based on tokens, tags, lemmas or all the three; same for the concordancer.

The collocation extractor currently works only with bigrams.

The concordancer is not 100% accurate. See "Known issues" section for more info.

=head1 KNOWN ISSUES

=over 4

=item B<1. Concordancer>

Currently, the concordancer reads each element only one time, which means that if a match is identified, the search for other matches will start again after the end of the concordance line. In the same way, if the begining of a match is found, but it turns out not to be a full match, the search will start again after this false match.

The problem is the smallest when the context wanted to build the concordances is small and when the pattern to identify is small and rare.

This should be fixed soon.

=item B<2. Root_path>

The program does not word if the root_path (in .config/config.json) contains white spaces.

=item B<3. Wiki texts>

There are some (very few) encoding errors in the .wiki files.

=back

=head1 AUTHOR

Laurane Castiaux <laurane.castiaux@student.uclouvain.be>

Original project: https://github.com/Reyla98/collExtractor

=head1 COPYRIGHT

Copyright (c) 2020 Laurane Castiaux.

Distributed and Licensed under provisions of the GNU General Public 
License v3.0, which is available at https://www.gnu.org/licenses/. 

This program is distributed in the hope that it will be useful, but 
WITHOUT ANY WARRANTY; without even the implied warranty of 
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU 
General Public License for more details.


This program uses Ngram Statistics Package (NSP) - Copyright (C) 2000-2003, Ted Pedersen 
and Satanjeev Banerjee, distributed under GNU Public Licence.

This program uses TreeTagger developed by Helmut Schmid at the Institute for 
Computational Linguistics of the University of Stuttgart.
=cut
