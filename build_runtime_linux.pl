use strict;

use lib ('.', "../../Tools/perl_lib","perl_lib");
use Cwd;
use Cwd 'abs_path';
use File::Path;
use Getopt::Long;
use Tools qw(InstallNameTool);

my $root = getcwd();
my $buildsroot = "$root/builds";
my $buildir = "$buildsroot/src";

my $monoroot = abs_path($root."/../Mono");
$monoroot = abs_path($root."/../mono") unless (-d $monoroot);
die ("Cannot find mono checkout in ../Mono or ../mono") unless (-d $monoroot);
print "Mono checkout found in $monoroot\n\n";

my $skipbuild=0;
my $debug = 0;
my $minimal = 0;
my $cleanbuild = 1;
my $build64 = 0;
my $build_armel = 0;
my $jobs = 1;

GetOptions(
   "skipbuild=i"=>\$skipbuild,
   "debug=i"=>\$debug,
   "minimal=i"=>\$minimal,
   "cleanbuild=i"=>\$cleanbuild,
   "build64=i"=>\$build64,
   "build-armel=i"=>\$build_armel,
   "jobs=i"=>\$jobs,
) or die ("illegal cmdline options");

die ("illegal cmdline options") if ($build64 and $build_armel);

my $teamcity=0;
if ($ENV{UNITY_THISISABUILDMACHINE})
{
	print "rmtree-ing $buildsroot because we're on a buildserver, and want to make sure we don't include old artifacts\n";
	rmtree("$buildsroot");
	$teamcity=1;
} else {
	print "not rmtree-ing $buildsroot, as we're not on a buildmachine";
	if (($debug==0) && ($skipbuild==0))
	{
		print "\n\nARE YOU SURE YOU DONT WANT TO MAKE A DEBUG BUILD?!?!?!!!!!\n\n\n";
	}
}

my $platform = $build64 ? 'linux64' : $build_armel ? 'linux-armel' : 'linux32' ;
my $bintarget = "$buildsroot/monodistribution/bin-$platform";
my $libtarget = "$buildsroot/embedruntimes/$platform";
my $etctarget = "$buildsroot/monodistribution/etc-$platform";


my $os = 'linux';
my $arch = $build64 ? 'x86_64' : $build_armel ? 'armel' : 'i386' ;
my $buildtarget = "$buildir/$os-$arch";
my $cachefile = "$buildir/$os-$arch.cache";

if ($minimal)
{
	$libtarget = "$buildsroot/embedruntimes/$platform-minimal";
}

print("libtarget: $libtarget\n");

system("rm -f $bintarget/mono");
system("rm -f $libtarget/libmono.so");
system("rm -f $libtarget/libmono-static.a");
system("rm -f $libtarget/libMonoPosixHelper.so");

if (not $skipbuild)
{
	mkpath("$buildir");

	my $archflags = '';

	if (not $build64 and not $build_armel)
	{
		$archflags = '-m32';
	}
	if ($build_armel)
	{
		$archflags = '-marm -DARM_FPU_NONE';
	}
	if ($debug)
	{
		$ENV{CFLAGS} = "$archflags -g -O0";
	} else
	{
		$ENV{CFLAGS} = "$archflags -Os";  #optimize for size
	}
	$ENV{CXXFLAGS} = $ENV{CFLAGS};
	$ENV{LDFLAGS} = "$archflags";

	if ($cleanbuild == 1) {
		system("rm $cachefile");
		if (chdir("$buildtarget") eq 1) {
			system("make clean");
		}
	}

	chdir("$monoroot/eglib") eq 1 or die ("Failed chdir 1");
	system("autoreconf -i") eq 0 or die ("Failed autoreconfing eglib");

	chdir("$monoroot") eq 1 or die ("Failed chdir 2");
	system("autoreconf -i") eq 0 or die ("Failed autoreconfing mono");


	my @autogenparams = ();
	unshift(@autogenparams, "--cache-file=$cachefile");
	unshift(@autogenparams, "--disable-mcs-build");
	unshift(@autogenparams, "--with-glib=embedded");
	unshift(@autogenparams, "--disable-nls");  #this removes the dependency on gettext package
	unshift(@autogenparams, "--disable-parallel-mark");  #this causes crashes
	if(not $build64 and not $build_armel)
	{
		unshift(@autogenparams, "--build=i686-pc-linux-gnu");  #Force x86 build
	}

	if ($minimal)
	{
		unshift(@autogenparams,"--enable-minimal=aot,logging,com,profiler,debug");
	}

	print("\n\n\n\nCalling configure with these parameters: ");
	system("echo", @autogenparams);
	print("\n\n\n\n\n");

	chdir("$buildir") eq 1 or die ("Failed chdir 3");
	system("calling $monoroot/configure",@autogenparams);
	system("$monoroot/configure", @autogenparams) eq 0 or die ("failing configuring mono");
	system("make -j$jobs") eq 0 or die ("failing running make for mono");
}

mkpath($bintarget);
mkpath($libtarget);
mkpath("$etctarget/mono");

print "Copying libmono.so\n";
system("cp", "$buildtarget/mono/mini/.libs/libmono.so.0","$libtarget/libmono.so") eq 0 or die ("failed copying libmono.so.0");

print "Copying libmono.a\n";
system("cp", "$buildtarget/mono/mini/.libs/libmono.a","$libtarget/libmono-static.a") eq 0 or die ("failed copying libmono.a");

print "Copying libMonoPosixHelper.so\n";
system("cp", "$buildtarget/support/.libs/libMonoPosixHelper.so","$libtarget/libMonoPosixHelper.so") eq 0 or die ("failed copying libMonoPosixHelper.so");

if ($ENV{"UNITY_THISISABUILDMACHINE"})
{
	system("strip $libtarget/libmono.so") eq 0 or die("failed to strip libmono (shared)");
	system("strip $libtarget/libMonoPosixHelper.so") eq 0 or die("failed to strip libMonoPosixHelper (shared)");
	system("echo \"mono-runtime-$platform = $ENV{'BUILD_VCS_NUMBER_mono_unity_2_10_2'}\" > $root/builds/versions.txt");
}

system("ln","-f","$buildtarget/mono/mini/mono","$bintarget/mono") eq 0 or die("failed symlinking mono executable");
system("ln","-f","$buildtarget/mono/metadata/pedump","$bintarget/pedump") eq 0 or die("failed symlinking pedump executable");
system('cp',"$buildtarget/data/config","$etctarget/mono/config");
system("chmod","-R","755",$bintarget);
