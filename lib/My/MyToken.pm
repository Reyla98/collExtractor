# -*- coding: utf-8 -*-

#This module is part of collExtractor.pl

use strict;
use warnings;

package MyToken;

sub new {
	my $class = $_[0];
	my $self = {
		token => $_[1],
		tag => $_[2],
		lemma => $_[3],
		all => "$_[1] $_[2] $_[3]"
	};
	bless $self, $class;
	return $self;
}
1;