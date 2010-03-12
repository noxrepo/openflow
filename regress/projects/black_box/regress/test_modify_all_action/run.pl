#!/usr/bin/perl -w
# test_set_nw_dst

use strict;
use OF::Includes;

sub get_define {
        my $val = shift;
        my $retval = `grep \"#define $val \" \$OF_ROOT/include/openflow/openflow.h | awk '{print \$3}'`;
        chomp $retval;
        return $retval;
}

### This function has been ported from a regression test library in OpenFlow1.0.
### Some arguments and variables don't apply to 0.8.9 (but not affect the test)
sub create_flow_mod_from_udp_actionbytes {
        my ( $ofp, $udp_pkt, $in_port, $max_idle, $flags,
                $wildcards, $mod_type, $action_bytes, $vlan_id,
                $nw_tos, $cookie) = @_;

        $cookie = 0 if !defined($cookie);

        my $length = $ofp->sizeof('ofp_flow_mod') + length $action_bytes;

        my $of_ver = get_define('OFP_VERSION');

        my $hdr_args = {
                version => $of_ver,
                type    => $enums{'OFPT_FLOW_MOD'},
                length  => $length,
                xid     => 0x0000000
        };

        # might be cleaner to convert the exported colon-hex MAC addrs
        #print ${$udp_pkt->{Ethernet_hdr}}->SA . "\n";
        #print ${$test_pkt->{Ethernet_hdr}}->SA . "\n";
        my $ref_to_eth_hdr = ( $udp_pkt->{'Ethernet_hdr'} );
        my $ref_to_ip_hdr  = ( $udp_pkt->{'IP_hdr'} );

        # pointer to array
        my $eth_hdr_bytes    = $$ref_to_eth_hdr->{'bytes'};
        my $ip_hdr_bytes     = $$ref_to_ip_hdr->{'bytes'};
        my @dst_mac_subarray = @{$eth_hdr_bytes}[ 0 .. 5 ];
        my @src_mac_subarray = @{$eth_hdr_bytes}[ 6 .. 11 ];

        my @src_ip_subarray = @{$ip_hdr_bytes}[ 12 .. 15 ];
        my @dst_ip_subarray = @{$ip_hdr_bytes}[ 16 .. 19 ];

        my $src_ip =
          ( ( 2**24 ) * $src_ip_subarray[0] +
                  ( 2**16 ) * $src_ip_subarray[1] +
                  ( 2**8 ) * $src_ip_subarray[2] +
                  $src_ip_subarray[3] );
        my $dst_ip =
          ( ( 2**24 ) * $dst_ip_subarray[0] +
                  ( 2**16 ) * $dst_ip_subarray[1] +
                  ( 2**8 ) * $dst_ip_subarray[2] +
                  $dst_ip_subarray[3] );

        my $dl_vlan;
        my $dl_vlan_pcp;
        if (defined $vlan_id) {
                $dl_vlan = $vlan_id & 0x0fff;
                $dl_vlan_pcp = (($vlan_id >> 13) & 0x0007);
        } else {
                $dl_vlan = 0xffff;
                $dl_vlan_pcp = 0x0;
        }

        my $match_nw_tos;
        if (defined $nw_tos) {
            $match_nw_tos = $nw_tos & 0xfc;
        } else {
            $match_nw_tos = 0;
        }

        my $match_args = {
                wildcards => $wildcards,
                in_port   => $in_port,
                dl_src    => \@src_mac_subarray,
                dl_dst    => \@dst_mac_subarray,
                dl_vlan   => $dl_vlan,
                dl_type   => 0x0800,
        #        dl_vlan_pcp => $dl_vlan_pcp,
                nw_src    => $src_ip,
                nw_dst    => $dst_ip,
        #        nw_tos    => $match_nw_tos,
                nw_proto  => 17,                                  #udp
                tp_src    => ${ $udp_pkt->{UDP_pdu} }->SrcPort,
                tp_dst    => ${ $udp_pkt->{UDP_pdu} }->DstPort
        };

        # organize flow_mod packet
        my $flow_mod_args = {
                header => $hdr_args,
                match  => $match_args,
                command   => $enums{"$mod_type"},
                idle_timeout  => $max_idle,
                hard_timeout  => $max_idle,
                flags  => $flags,
                priority => 0,
                buffer_id => -1,
                out_port => $enums{'OFPP_NONE'},
                cookie => $cookie,
        };
        my $flow_mod = $ofp->pack( 'ofp_flow_mod', $flow_mod_args );
        my $flow_mod_pkt = $flow_mod . $action_bytes;
        return $flow_mod_pkt;
}

sub send_expect_exact {
    my ($ofp, $sock, $options_ref, $in_port_offset, $out_port_offset, $max_idle, $pkt_len) = @_;

    my $in_port = $in_port_offset + $$options_ref{'port_base'};
    my $out_port = $out_port_offset + $$options_ref{'port_base'};

    my $vlan_id = int(rand(4094)+1);
    my $vlan_pcp = int(rand(8));
    my $vlan = ($vlan_pcp << 13)+$vlan_id;
    my $vlan_id_exp = 4096-$vlan_id;
    my $vlan_pcp_exp = 7-$vlan_pcp;
    my $vlan_exp = ($vlan_pcp_exp << 13)+$vlan_id_exp;

    # in_port refers to the flow mod entry's input

    # Create the payload ourselves to make sure the two packets match
    # Jean II
    my $pkt_payload = [map {int(rand(256))} (1..($pkt_len - 8 - 4 - 16 - 4 - 14))];


    # In Openflow0.8.9, vlan_pcp will be ignored.
    # This is the packet we are sending... - Jean II
    my $test_pkt_args = {
	DA     => "00:00:00:00:00:" . sprintf( "%02d", $out_port ),
	SA     => "00:00:00:00:00:" . sprintf( "%02d", $in_port ),
	VLAN_ID => $vlan,
	src_ip => "192.168.200." .     ( $in_port ),
	dst_ip => "192.168.201." .     ( $out_port ),
	tos => 0x0,
	ttl => 64,
	len => $pkt_len,
	src_port => $in_port,
	dst_port => $out_port,
	data => $pkt_payload
    };
    my $test_pkt = new NF2::UDP_pkt(%$test_pkt_args);

    # This is the packet we are expecting to receive - Jean II
    my $expect_pkt_args = {
	DA     => "00:00:00:00:00:" . sprintf( "%02d", $in_port ),
	SA     => "00:00:00:00:00:" . sprintf( "%02d", $out_port ),
	VLAN_ID => $vlan_exp,
	src_ip => "192.168.201." .     ( $out_port ),
	dst_ip => "192.168.200." .     ( $in_port ),
	tos => 0x0,
	ttl => 64,
	len => $pkt_len,
	src_port => $out_port,
	dst_port => $in_port,
	data => $pkt_payload
    };
    my $expect_pkt = new NF2::UDP_pkt(%$expect_pkt_args);

    #print HexDump ($test_pkt->packed);

    my $wildcards = 0x0;		       # exact match
    my $flags = $enums{'OFPFF_SEND_FLOW_REM'}; # want flow expiry

    # Get the various addresses in the expected packet - Jean II
    my $chg_val_dl_da = ${$expect_pkt->{Ethernet_hdr}}->DA;
    my $chg_val_dl_sa = ${$expect_pkt->{Ethernet_hdr}}->SA;
    my $chg_val_nw_dst = ${$expect_pkt->{IP_hdr}}->dst_ip;
    my $chg_val_nw_src = ${$expect_pkt->{IP_hdr}}->src_ip;
    my @dl_da_addr_chg = NF2::PDU::get_MAC_address($chg_val_dl_da);
    my @dl_sa_addr_chg = NF2::PDU::get_MAC_address($chg_val_dl_sa);
    my $nw_dst_addr_chg;
    my $ok_org;
    ($nw_dst_addr_chg, $ok_org) = NF2::IP_hdr::getIP($chg_val_nw_dst);
    my $nw_src_addr_chg;
    ($nw_src_addr_chg, $ok_org) = NF2::IP_hdr::getIP($chg_val_nw_src);

    # Create the desired rewrite actions
    my @pad_2 = (0,0);
    my @pad_3 = (0,0,0);
    my @pad_6 = (0,0,0,0,0,0);
    my $action_mod_dl_da_args = {
	type => $enums{'OFPAT_SET_DL_DST'},
	len  => $ofp->sizeof('ofp_action_dl_addr'),
	dl_addr => \@dl_da_addr_chg,
	pad  => \@pad_6,
    };
    my $action_mod_dl_da = $ofp->pack('ofp_action_dl_addr', $action_mod_dl_da_args);
    my $action_mod_dl_sa_args = {
	type => $enums{'OFPAT_SET_DL_SRC'},
	len  => $ofp->sizeof('ofp_action_dl_addr'),
	dl_addr => \@dl_sa_addr_chg,
	pad  => \@pad_6,
    };
    my $action_mod_dl_sa = $ofp->pack('ofp_action_dl_addr', $action_mod_dl_sa_args);
    my $action_mod_nw_dst_args = {
	type => $enums{'OFPAT_SET_NW_DST'},
	len => $ofp->sizeof('ofp_action_nw_addr'),
	nw_addr => $nw_dst_addr_chg,
    };
    my $action_mod_nw_dst = $ofp->pack( 'ofp_action_nw_addr', $action_mod_nw_dst_args );
    my $action_mod_nw_src_args = {
	type => $enums{'OFPAT_SET_NW_SRC'},
	len => $ofp->sizeof('ofp_action_nw_addr'),
	nw_addr => $nw_src_addr_chg,
    };
    my $action_mod_nw_src = $ofp->pack( 'ofp_action_nw_addr', $action_mod_nw_src_args );
    my $action_mod_vlan_vid_args = {
	type => $enums{'OFPAT_SET_VLAN_VID'},
	len => $ofp->sizeof('ofp_action_vlan_vid'),
	vlan_vid => $vlan_id_exp,
	pad  => \@pad_2,
    };
    my $action_mod_vlan_vid = $ofp->pack( 'ofp_action_vlan_vid', $action_mod_vlan_vid_args );
    my $action_mod_vlan_pcp_args = {
	type => $enums{'OFPAT_SET_VLAN_PCP'},
	len => $ofp->sizeof('ofp_action_vlan_pcp'),
	vlan_pcp => $vlan_pcp_exp,
	pad  => \@pad_3,
    };
    my $action_mod_vlan_pcp = $ofp->pack( 'ofp_action_vlan_pcp', $action_mod_vlan_pcp_args );
    my $action_mod_tp_src_args = {
	type => $enums{'OFPAT_SET_TP_SRC'},
	len => $ofp->sizeof('ofp_action_tp_port'),
	tp_port => $out_port,
	pad  => \@pad_2,
    };
    my $action_mod_tp_src = $ofp->pack( 'ofp_action_tp_port', $action_mod_tp_src_args );
    my $action_mod_tp_dst_args = {
	type => $enums{'OFPAT_SET_TP_DST'},
	len => $ofp->sizeof('ofp_action_tp_port'),
	tp_port => $in_port,
	pad  => \@pad_2,
    };
    my $action_mod_tp_dst = $ofp->pack( 'ofp_action_tp_port', $action_mod_tp_dst_args );

    # Output action to get the packet out someplace - Jean II
    my $action_output_args = {
	type => $enums{'OFPAT_OUTPUT'},
	len => $ofp->sizeof('ofp_action_output'),
	port => $out_port,
	max_len => 0,                                     # send entire packet
    };
    my $action_output = $ofp->pack( 'ofp_action_output', $action_output_args );

    # Aggregate all actions together
    my $action_bytes = ($action_mod_dl_da . $action_mod_dl_sa . $action_mod_nw_dst . $action_mod_nw_src .
                       $action_mod_vlan_vid . $action_mod_vlan_pcp .
                       $action_mod_tp_src . $action_mod_tp_dst .
                       $action_output);

    my $flow_mod_pkt =
	  create_flow_mod_from_udp_actionbytes( $ofp, $test_pkt, $in_port, $max_idle, $flags, $wildcards, 'OFPFC_ADD', $action_bytes, $vlan);

    #print HexDump($flow_mod_pkt);

    # Send 'flow_mod' message
    print $sock $flow_mod_pkt;
    print "sent flow_mod message\n";

    # Give OF switch time to process the flow mod
    usleep($$options_ref{'send_delay'});

    # Send a packet - ensure packet comes out desired port
    nftest_send("eth" . ($in_port_offset + 1), $test_pkt->packed);
    nftest_expect("eth" . ($out_port_offset + 1), $expect_pkt->packed);
}

sub test_set_nw_dst {
    my ($ofp, $sock, $options_ref, $i, $j, $wildcards) = @_;

    my $max_idle =  $$options_ref{'max_idle'};
    my $pkt_len = $$options_ref{'pkt_len'};
    my $pkt_total = $$options_ref{'pkt_total'};

    send_expect_exact($ofp, $sock, $options_ref, $i, $j, $max_idle, $pkt_len);
    wait_for_flow_expired($ofp, $sock, $options_ref, $pkt_len, $pkt_total);
}

sub my_test {
    my ($sock, $options_ref) = @_;

    enable_flow_expirations( $ofp, $sock );

    # send from every port to every other port
    for_all_port_pairs($ofp, $sock, $options_ref, \&test_set_nw_dst, 0x0);
}

run_black_box_test(\&my_test, \@ARGV);
