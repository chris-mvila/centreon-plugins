#
# Copyright 2023 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package apps::pvx::restapi::mode::networkconnection;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

sub prefix_instances_output {
    my ($self, %options) = @_;

    return $options{instance_value}->{instance_label} . " '" . $options{instance_value}->{key} . "' ";
}

sub set_counters {
    my ($self, %options) = @_;

    $self->{maps_counters_type} = [
        { name => 'instances', type => 1, cb_prefix_output => 'prefix_instances_output', message_multiple => 'All connection metrics are ok' },
    ];
    
    $self->{maps_counters}->{instances} = [
        { label => 'ratio', nlabel => 'connections.ratio.percentage', set => {
                key_values => [ { name => 'syns_ratio' }, { name => 'key' }, { name => 'instance_label' } ],
                output_template => 'ratio: %.2f',
                perfdatas => [
                    { label => 'ratio', template => '%.2f',
                      min => 0, label_extra_instance => 1, instance_use => 'key' }
                ]
            }
        },
        { label => 'attempt', nlabel => 'connections.attempts.persecond', set => {
                key_values => [ { name => 'syns' }, { name => 'key' }, { name => 'instance_label' } ],
                output_template => 'connections attempts: %.2f conn/s',
                perfdatas => [
                    { label => 'attempt', template => '%.2f',
                      min => 0, unit => 'connections/s', label_extra_instance => 1, instance_use => 'key' }
                ]
            }
        },
        { label => 'successful', nlabel => 'connections.successful.persecond', set => {
                key_values => [ { name => 'ct_count' }, { name => 'key' }, { name => 'instance_label' } ],
                output_template => 'successful connections: %.2f conn/s',
                perfdatas => [
                    { label => 'successful', template => '%.2f',
                      min => 0, unit => 'connections/s', label_extra_instance => 1, instance_use => 'key' }
                ]
            }
        },
        { label => 'connection-time', nlabel => 'connection.time.milliseconds', set => {
                key_values => [ { name => 'ct' }, { name => 'key' }, { name => 'instance_label' } ],
                output_template => 'average connection time: %.3f ms',
                perfdatas => [
                    { label => 'connection_time', template => '%.3f',
                      min => 0, unit => 'ms', label_extra_instance => 1, instance_use => 'key' }
                ]
            }
        }
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $options{options}->add_options(arguments => {
        'instance:s' => { name => 'instance', default => 'layer' },
        'top:s'      => { name => 'top' },
        'filter:s'   => { name => 'filter' },
        'from:s'     => { name => 'from' }
    });

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    if (!defined($self->{option_results}->{from}) || $self->{option_results}->{from} eq '') {
        $self->{output}->add_option_msg(short_msg => "Need to specify --from option as a PVQL object.");
        $self->{output}->option_exit();
    }

    if (!defined($self->{option_results}->{instance}) || $self->{option_results}->{instance} eq '') {
        $self->{output}->add_option_msg(short_msg => "Need to specify --instance option as a PVQL object.");
        $self->{output}->option_exit();
    }

    $self->{pvql_timeframe} = defined($self->{option_results}->{timeframe}) ? $self->{option_results}->{timeframe} : 900;
}

sub manage_selection {
    my ($self, %options) = @_;

    my $instance_label = $self->{option_results}->{instance};
    $instance_label =~ s/\./ /g;
    $instance_label =~ s/(\w+)/\u\L$1/g;

    $self->{instances} = {};

    my $apps;
    if ($self->{option_results}->{instance} =~ /application/) {
        my $results = $options{custom}->get_endpoint(url_path => '/get-configuration');
        $apps = $results->{applications};
    }
    
    my $results = $options{custom}->query_range(
        query => 'syns.ratio, syns, ct.count, ct',
        instance => $self->{option_results}->{instance},
        top => $self->{option_results}->{top},
        filter => $self->{option_results}->{filter},
        from => $self->{option_results}->{from},
        timeframe => $self->{pvql_timeframe},
    );

    foreach my $result (@{$results}) {
        next if (!defined(${$result->{key}}[0]));
        my $instance;
        $instance = ${$result->{key}}[0]->{value} if (defined(${$result->{key}}[0]->{value}));
        $instance = ${$result->{key}}[0]->{status} if (defined(${$result->{key}}[0]->{status}));
        $self->{instances}->{$instance}->{key} = $instance;
        $self->{instances}->{$instance}->{key} = $apps->{$instance}->{name} if (defined($apps->{$instance}->{name}) && $self->{option_results}->{instance} =~ /application/);
        $self->{instances}->{$instance}->{syns_ratio} = (defined(${$result->{values}}[0]->{value})) ? ${$result->{values}}[0]->{value} : 1;
        $self->{instances}->{$instance}->{syns} = ${$result->{values}}[1]->{value} / $self->{pvql_timeframe};
        $self->{instances}->{$instance}->{ct_count} = ${$result->{values}}[2]->{value} / $self->{pvql_timeframe};
        $self->{instances}->{$instance}->{ct} = (defined(${$result->{values}}[3]->{value})) ? ${$result->{values}}[3]->{value} * 1000 : 0;
        $self->{instances}->{$instance}->{instance_label} = $instance_label;
    }

    if (scalar(keys %{$self->{instances}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No instances or results found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check instances connection metrics.

=over 8

=item B<--instance>

Filter on a specific instance (must be a PVQL object, Default: 'layer')

(Object 'application' will be mapped with applications name)

=item B<--filter>

Add a PVQL filter (example: --filter='application = "mysql"')

=item B<--from>

Add a PVQL from clause to filter on a specific layer (example: --from='tcp')

=item B<--top>

Only search for the top X results (top is made on 'ratio').

=item B<--warning-*>

Warning threshold.
Can be: 'ratio', 'attempt' (conn/s), 'successful' (conn/s), 'connection-time' (ms).

=item B<--critical-*>

Critical threshold.
Can be: 'ratio', 'attempt' (conn/s), 'successful' (conn/s), 'connection-time' (ms).

=item B<--filter-counters>

Only display some counters (regexp can be used).
Example: --filter-counters='ratio'

=back

=cut
