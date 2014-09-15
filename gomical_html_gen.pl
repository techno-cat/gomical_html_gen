use v5.14;
use strict;
use warnings;

use JSON;
use Encode qw(encode);
use Path::Tiny;
use Data::ICal;
use Time::Piece;
use Text::Xslate qw(mark_raw);
use FindBin qw($Bin);

my $empty = ' ';
my %gomi_to_index = (
    $empty                      => 1,
    '燃やせるごみ'              => 2,
    '燃やせないごみ'            => 3,
    '容器包装プラスチック'      => 4,
    'びん・缶・ペットボトル'    => 5,
    '雑がみ'                    => 6,
    '枝・葉・草'                => 7
);

my @html_src = (
    { text => ''                , style => 'cls_padding'                },
    { text => $empty            , style => 'cls_none'                   },
    { text => '燃やせるごみ'    , style => 'cls_combustible'            },
    { text => '燃やせないごみ'  , style => 'cls_incombustible'          },
    { text => '容器プラ'        , style => 'cls_plasticcontainer'       },
    { text => 'びん・缶・ペット', style => 'cls_bottle_can_petbottle'   },
    { text => '雑がみ'          , style => 'cls_roughpaper'             },
    { text => '枝・葉・草'      , style => 'cls_branch_leaf_grass'      }
);

if ( (not @ARGV) or (not -e $ARGV[0]) ) {
    say "Usage:
    perl $0 json_path";
    exit( 0 );
}

open( my $fh, '<', $ARGV[0] ) or die;
my $unicode_json_text = do { local $/; <$fh>; };
my $json = from_json( $unicode_json_text, { utf8  => 1 } );

my $json_dir = path( $ARGV[0] )->parent();
#say 'dir : ', $json_dir;

# todo: 札幌市の公式ページに合わせた並びにする
my @wards = sort( keys %{$json} );
#print encode('UTF-8', $_), "\n" for @wards;
#say "--------------------------";

my $dst_dir = path( $Bin, 'gomical_html' );
if ( not -e $dst_dir ) {
    say "Create: ", $dst_dir;
    mkdir $dst_dir or die "\"$dst_dir\" cannot create.";
}
elsif ( not -d $dst_dir ) {
    die "\"$dst_dir\" is not directory.";
}

my $path_index = path( $dst_dir, 'index.html' );

my @html_tree = ();
my $i = 0;
foreach my $ward ( @wards ) {
    #say encode( 'UTF-8', $ward );

    # todo: 住所用のソート
    my @streets = sort( keys %{$json->{$ward}} );

    my @children = ();
    foreach my $street ( @streets ) {
        my $dst_path = path( $dst_dir, sprintf('%03d.html', $i) );
        push @children, {
            ward     => $ward,
            street   => $street,
            dst_path => $dst_path,
            href     => $dst_path->relative($dst_dir)
        };

        $i++;
    }

    push @html_tree, {
        ward     => $ward,
        children => \@children
    };
}

my $xslate = Text::Xslate->new(
    path => [
        "./templates"
    ]
);
my $footer = $xslate->render( "footer.tx", {} );

# index.htmlの書き出し
{
    my $html = $xslate->render( "index.tx", {
        title     => "家庭ごみ収集日カレンダー",
        html_tree => \@html_tree,
        footer    => $footer
    } );

    write_html( $path_index, $html );
}

# カレンダーの書き出し
foreach my $node ( @html_tree ) {
    foreach ( @{$node->{children}} ) {
        my ( $ward, $street, $dst_path ) = ( $_->{ward}, $_->{street}, $_->{dst_path} );
        say encode('UTF-8', '  ' . $ward . ':' . $street), ':', $dst_path;

        my $path = path( $json_dir, $json->{$ward}->{$street} );
        my $ical = Data::ICal->new( filename => $path ) or die;
        my $src = create_calendar_src( $ward, $street, parse_ical_data($ical) );

        my @calendars = map {
            $xslate->render( "calendar.tx", {
                year     => $_->{year},
                month    => $_->{month},
                schedule => $_->{schedule}
            } );
        } @{$src};

        my $html = $xslate->render( "nnn.tx", {
            title     => "$ward - $street",
            calendars => \@calendars,
            footer    => $footer
        } );

        write_html( $dst_path, $html );
    }
}

sub write_html {
    my ( $dst_path, $html ) = @_;

    say "Write: ", $dst_path;
    open my $fh, '>', $dst_path or die "\"$dst_path\" cannot open.";
    binmode $fh, ':utf8';
    print $fh $html;
    close $fh;
}

sub create_calendar_src {
    my ( $ward, $street, $src ) = @_;

    my $padding_data = {
        day => '',
        text => $html_src[0]->{text},
        style => $html_src[0]->{style},
        wday => ''
    };

    my @calendar_src = ();
    foreach my $yyyy ( sort(keys %{$src}) ) {
        foreach my $MM ( sort { $a <=> $b; } (keys %{$src->{$yyyy}}) ) {
            my $t = Time::Piece->strptime( "$yyyy-$MM-1", '%Y-%m-%d' );

            my @schedule = map {
                my $yyyy_MM_dd = sprintf( "%d-%d-%d", $yyyy, $MM, $_ );
                my $wday = lc Time::Piece->strptime( $yyyy_MM_dd, '%Y-%m-%d' )->wdayname();

                +{
                    day   => $_,
                    text  => $html_src[1]->{text},
                    style => "cls_$wday " . $html_src[1]->{style},
                    wday  => $wday
                };
            } 1..$t->month_last_day();

            unshift @schedule, +{}; # add dummy
            foreach ( @{$src->{$yyyy}->{$MM}} ) {
                my $summary = $_->{summary};
                if ( not exists $gomi_to_index{$summary} ) {
                    die $summary, ' not defined!';
                }

                my $s = $html_src[$gomi_to_index{$summary}];
                my $wday = $schedule[$_->{dd}]->{wday};
                $schedule[$_->{dd}]->{text} = $s->{text};
                $schedule[$_->{dd}]->{style} = "cls_$wday " . $s->{style};
            }
            shift @schedule; # del dummy

            my @monthly = ();
            my @weekly = ();

            my $offset = $t->day_of_week(); # Sunday: 0
            for (my $i=0; $i<$offset; $i++) {
                push @weekly, $padding_data;
            }

            while ( @schedule ) {
                push @weekly, shift(@schedule);
                if ( 7 <= scalar(@weekly) ) {
                    my @tmp = @weekly;
                    push @monthly, \@tmp;
                    @weekly = ();
                }
            }

            if ( @weekly ) {
                while ( scalar(@weekly) < 7 ) {
                    push @weekly, $padding_data;
                }

                my @tmp = @weekly;
                push @monthly, \@tmp;
            }

            push @calendar_src, +{
                year     => $t->year,
                month    => $t->mon,
                schedule => \@monthly
            };
        }
    }

    return \@calendar_src;
}

sub calc_days_of {
    my ( $year, $mon ) = @_;

    my $t = Time::Piece->strptime( "$year-$mon-1", '%Y-%m-%d' );
    return $t->month_last_day();
}

sub parse_ical_data {
    my $ical = shift;

    my %result = ();
    foreach my $entry ( @{$ical->{entries}} ) {
        my $date = $entry->{properties}->{dtstart}[0]->{value};
        my $summary = $entry->{properties}->{summary}[0]->{value};
        my @tmp = $date =~ /(\d{4})(\d{2})(\d{2})/;
        my ( $yyyy, $MM, $dd ) = map { int($_) } @tmp;

        if ( not exists $result{$yyyy} ) {
            $result{$yyyy} = {};
        }

        if ( not exists $result{$yyyy}->{$MM} ) {
            $result{$yyyy}->{$MM} = [];
        }

        push @{$result{$yyyy}->{$MM}}, +{
            yyyy => $yyyy,
            MM => $MM,
            dd => $dd,
            summary => $summary
        };
    }

    return \%result;
}

=encoding utf-8

=head1 NAME

gomical_html_gen.pl - gomical HTML generator

=head1 SYNOPSIS

    $ perl gomical_html_gen.pl path/to/area.json

=head1 DESCRIPTION

    iCalデータとJSONから、HTMLを出力するスクリプト

    000〜xxx.htmlとindex.htmlは、import.plによって出力される
    .
    ├── gomical_html
    │   ├── 000.html
    │   ├── 001.html
    │   ├── 002.html
    │   ・
    │   ・
    │   ・
    │   ├── 280.html
    │   ├── 281.html
    │   ├── 282.html
    │   ├── css
    │   │   └── main.css
    │   └── index.html
    ├── gomical_html_gen.pl
    └── templates
        ├── calendar.tx
        ├── footer.tx
        ├── index.tx
        └── nnn.tx

=head1 LICENSE

Copyright (C) neko.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

neko E<lt>techno.cat.miau@gmail.comE<gt>

=cut
