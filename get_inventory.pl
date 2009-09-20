#!/usr/bin/perl -w
# Ryan's Linux Inventory Script version 2.5 (September 20th, 2009)
# 
# This program is designed to gather Linux hardware information, such as 
# total installed memory, disk sizes and model names, CPU information, and 
# more.
#
# If you like this program, please send me an email to rtwomey -AT- dracoware -DOT- com
# 
# Copyright 2004 - 2009 Ryan Twomey
#
# This script is dual-licensed under the Apache License, Version 2.0 and 
# the GNU General Public License Version 2.  You choose which license you 
# wish to apply to your usage of this software.
# 
# -------------------------- GNU GPL License Notice --------------------------
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
# ----------------------------------------------------------------------------
#
# -------------------------- Apache License Notice ---------------------------
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------
# 
# Changelog
#   1.0 April 3rd, 2004  - Initial version, gathers system info
#   1.1 April 6th, 2004  - First public release (cosmetic improvements, etc)
#   1.2 September 23rd, 2004 - Fixed disk capacity bug (Rolf Holtsmark)
#   1.3 December 13th, 2004  - Fixed typo (lspci where uname belonged), 
#                              better 2.6 IDE support, DVD recognition,
#                              cleaned up PCI scanning 
#                              (Andrew Medico <amedico@ccs.neu.edu>)
#   1.4 March 3rd, 2005  - Added display of network interfaces (Neil Quiogue)
#   1.5 April 14th, 2005 - Fixed output of disk sizes to be more readable
#   								(GB printed, as well as byte count - John Vestrum)
#   2.0 January 26th, 2006 - Added SCSI support and IDE disk cleanup.  Also 
#                            released under dual license (GPL & Apache v2)
#   2.1 December 30th, 2008 - Minor bug fixes - immeëmosol
#   2.5 September 20, 2009 - Added USB scan (Jay Ridgley)

use strict;
use Sys::Hostname;
use Cpuinfo;
use HostIP;

# get all the information
sub main()
{
	my $host = hostname;
	my $disk_info = get_disk_info();
	my $cpuinfo = get_cpu_info();
	my $meminfo = get_mem_info();
	my $netinfo = get_net_info();
	my $allnetinfo = get_all_net_info();
	my $pci_hw = get_pci_hardware();
	my $kernel = get_kernel();
	
	# add USB scan - CDJ Systems 07/25/09
	my $usb_list = get_usb_info();
	
	# print out the report
	print "Statistics of machine '" . $host . "'\n";
	print "  * " . $cpuinfo . "\n";
	print $kernel;
	print $meminfo . "\n";
	print $netinfo;
	print $allnetinfo;
	print $pci_hw;
	print $usb_list;
	print $disk_info;
}

# get_pci_hardware - get PCI card info (like graphics card and network controller)
sub get_pci_hardware()
{
	my $hw = "";
	
	open(PIPE, "lspci |") || die "Couldn't execute lspci";
	my $output = <PIPE>;
	close(PIPE);
	
	chomp $output;
	my @lines = split("\n", $output);
	foreach my $line (@lines)
	{
		chomp $line;
		
		# get the graphics card type
		my ($type, $model) = split(/: /, (split(/ /, $line, 2))[1], 2);
		if($type =~ m/VGA/) {
			$hw .= "  * Graphics card: $model\n";
		}
		elsif($type =~ m/Ethernet/) {
			$hw .= "  * Network controller: $model\n";
		}
		elsif($type =~ m/Multimedia/) {
			$hw .= "  * Sound card: $model\n";
		}
		elsif($type =~ m/SCSI/) {
			$hw .= "  * SCSI card: $model\n";
		}
	}

	return $hw;
}

# get_usb_info - get the USB info - CDJ Systems - 07/25/09
sub get_usb_info()
{
	my $usb = "";

	open(PIPE, "lsusb|sort|") || die "Couldn't execute lsusb";
	my $output = <PIPE>;
	close(PIPE);

	$usb .= "  * USB Information:\n";
	
	chomp $output;
	my @lines = split("\n", $output);
	foreach my $line (@lines)
	{
		chomp $line;
		$usb .= "\t$line\n";
	}
	
	return $usb;
}

# get_kernel - get the linux kernel we're running
sub get_kernel()
{
	my $kernel;

	open(PIPE, "uname -rv |") || die "Couldn't execute uname";
	my $output = <PIPE>;
	close(PIPE);
	
	chomp $output;
	$kernel = "  * Kernel: " . $output . "\n";
	return $kernel;
}

# get_mem_info - get the memory installed/used amounts
sub get_mem_info()
{
	my $meminfo;
	
	open(PIPE, "cat /proc/meminfo |") || die "Couldn't cat /proc/meminfo";
	my $output = <PIPE>;
	close(PIPE);
	
	chomp $output;
	my @lines = split("\n", $output);
	foreach my $line (@lines)
	{
		chomp $line;
		
		# get the total memory
		if($line =~ m/MemTotal/) {
			my @parts = split(" ", $line);
			$meminfo .= "  * Memory total: " . $parts[1] . $parts[2];
		}
	}
	
	return $meminfo;
}

# get_disk_info - determine what hard drives are on the ide and/or scsi chain(s)
sub get_disk_info()
{
	my $disks;
	my $proc_dir = "/proc/ide";
	my $proc_scsi = "/proc/scsi/scsi";
	my $scsi_sg = "/proc/scsi/sg/devices";
	
	# 
	# check IDE chain
	#
	if(-e $proc_dir)
	{
		opendir(DIR, $proc_dir) or die "Can't open /proc/ide: $!";
		
		my $title = 0;
		
		# get each of the disks the system knows about
		my @disks = grep { /hd/ && -d "$proc_dir/$_" } readdir(DIR);
		foreach my $disk (@disks)
		{
			# get this disk's capacity
			my $capacity;
			if (open(DISKCAP, "$proc_dir/$disk/capacity")) {
				$capacity = <DISKCAP>;
				chomp $capacity;
				close(DISKCAP);
			} else {
				$capacity = -1;
			}
			
			# for some reason, the system has 0-capacity disks listed.
			next if $capacity == 0;
			
			# get the disk's model number
			open(DISKMOD, "$proc_dir/$disk/model") or die "Can't open $proc_dir/$disk/model";
			my $model = <DISKMOD>;
			chomp $model;
			close(DISKMOD);
			
			if(not $title) {
				$disks .= "\n  Attached IDE disks:\n";
				$title = 1;
			}
			
			if($model =~ /(CD-RW|CD-ROM|DVD)/) {
				# this isn't a hard drive
				$disks .= "    * $1 drive: $model\n";
			} else {
				$disks .= "    * Disk " . $disk . ": size: " . ($capacity*512) . " bytes (" . sprintf("%d",$capacity/1953125) . "GB), model: " . $model . "\n";
			}
		}
		
		closedir(DIR);
	}
	
	# 
	# check SCSI chain
	#
	if(-e $proc_scsi)
	{
		my @scsi_disks;
		
		open(SCSI, "$proc_scsi") or die "Can't open $proc_scsi: $!";
		
		# go through the scsi file and extract each disk
		my ($Channel, $Id, $Lun, $Vendor, $Model);
		while(<SCSI>)
		{
			# Format for this file is:
			# 
			# Host: scsi0 Channel: 01 Id: 08 Lun: 00
			#   Vendor: SEAGATE  Model: ST336607LC       Rev: 9B05
			#   Type:   Direct-Access                    ANSI SCSI revision: 03
			if(/Channel:\s+([^*]+)\sId:\s+([^*]+)\sLun:\s+([^*]+)\s/) {
				$Channel = $1;
				$Id = $2;
				$Lun = $3;
			}
			elsif(/Vendor:\s+([^*]+)\sModel:\s+(\S+)\s*Rev:\s+([^*]+)\s/) {
				$Vendor = $1;
				$Model = $2;
			}
			elsif(/Type:/ && $_ !~ /Processor/) {
				push @scsi_disks, {Vendor => $Vendor, Model => $Model, Channel => $Channel, Id => $Id, Lun => $Lun, Num => undef};
			}
		}
		
		close(SCSI);
		
		# lookup disk ID's from sg driver (/proc/scsi/sg/devices). Format of this file is:
		# host    chan    id      lun     type    opens   qdepth  busy    online
		if(open(SG, "$scsi_sg"))
		{
			my $i = 0;
			foreach my $line (<SG>)
			{
				chomp $line;
				my @e = split(" ", $line);
				
				$e[1] = "0" x ( 2 - length($e[1])) . $e[1];
				$e[2] = "0" x ( 2 - length($e[2])) . $e[2];
				$e[3] = "0" x ( 2 - length($e[3])) . $e[3];
				
				my $j = 0;
				foreach my $disk (@scsi_disks)
				{
					if($e[1] eq ${$disk}{Channel} && $e[2] eq ${$disk}{Id} && $e[3] eq ${$disk}{Lun}) {
						$scsi_disks[$j]{Num} = $i;
						$i++;
						last;
					}
					$j++;
				}
			}
			
			close(SG);
		}
		
		$disks .= "\n  Attached SCSI disks:\n";
		foreach my $disk (@scsi_disks)
		{
			$disks .=  '    * ';
			if (defined ${$disk}{Num}) {
				$disks .=  'Disk ' . map_num_to_disk(${$disk}{Num}) . ': ';
			}
			if (defined ${$disk}{Vendor}) {
				$disks .=  "${$disk}{Vendor} ";
			}
			if (defined ${$disk}{Model}) {
				$disks .=  "${$disk}{Model} ";
			}
			if (defined ${$disk}{Channel}) {
				$disks .=  "(Channel: ${$disk}{Channel} ";
			}
			if (defined ${$disk}{Id}) {
				$disks .=  "ID: ${$disk}{Id} ";
			}
			if (defined ${$disk}{Lun}) {
				$disks .=  "Lun: ${$disk}{Lun})";
			}
			$disks .=  "\n";
		}
	}
	
	return $disks;
}

# get_net_info - determine name and IP of this host
sub get_net_info()
{
	my $netinfo;
	
	# get network-related information
	my $ip_address = Sys::HostIP->ip;
	$netinfo = "  * Hostname: " . hostname . " @ $ip_address" . "\n";
	
	return $netinfo;
}

# get_all_net_info - determine the IP addresses of this host
sub get_all_net_info()
{
	my $netinfo = "  * Network Interfaces:\n";

	# get network-related information
	my $interfaces = Sys::HostIP->interfaces;
	foreach my $interface (keys %{$interfaces}) {
		$netinfo .= "\t$interface: ${$interfaces}{$interface}\n";
	}
	return $netinfo;
}

# get_cpu_info - determine how many and what type of cpus we have
sub get_cpu_info()
{
	my $cpuinfo = Linux::Cpuinfo->new();
	die ("Couldn't cat /proc/cpuinfo") unless ref $cpuinfo;
	
	# get cpu info
	my $cpus  = $cpuinfo->num_cpus();
	my $rep = "$cpus CPU";
	
	if($cpus > 1)
	{
		$rep .= "s:\n";
		my $i = 1;
		
		# go through each cpu
		foreach my $cpu ( $cpuinfo->cpus() ) {
			$rep .= " " if($i > 1);
         $rep .= "\tCPU$i = " . $cpu->model_name();
         $rep .= " @ " . $cpu->cpu_mhz() . "MHz\n";
			$i++;
		}
	}
	else {
		$rep .= ": ";
		
		foreach my $cpu ( $cpuinfo->cpus() ) {
			$rep .= $cpu->model_name();
			$rep .= " @ " . $cpu->cpu_mhz() . "MHz";
		}
	}

	return $rep;
}

sub map_num_to_disk($)
{
	my $num = shift @_;

	if ($num == 0)     { return "sda"; }
	elsif ($num == 1)  { return "sdb"; }
	elsif ($num == 2)  { return "sdc"; }
	elsif ($num == 3)  { return "sdd"; }
	elsif ($num == 4)  { return "sde"; }
	elsif ($num == 5)  { return "sdf"; }
	elsif ($num == 6)  { return "sdg"; }
	elsif ($num == 7)  { return "sdh"; }
	elsif ($num == 8)  { return "sdi"; }
	elsif ($num == 9)  { return "sdj"; }
	elsif ($num == 10) { return "sdk"; }
	elsif ($num == 11) { return "sdl"; }
	elsif ($num == 12) { return "sdm"; }
	elsif ($num == 13) { return "sdn"; }
	elsif ($num == 14) { return "sdo"; }
	elsif ($num == 15) { return "sdp"; }
	elsif ($num == 16) { return "sdq"; }
	elsif ($num == 17) { return "sdr"; }
	elsif ($num == 18) { return "sds"; }
	elsif ($num == 19) { return "sdt"; }
	elsif ($num == 20) { return "sdu"; }
	elsif ($num == 21) { return "sdv"; }
	elsif ($num == 22) { return "sdw"; }
	elsif ($num == 23) { return "sdx"; }
	elsif ($num == 24) { return "sdy"; }
	elsif ($num == 25) { return "sdz"; }
}

main();
