# == Class: sysstat
#
# A module to manage the sysstat configuration
#
class sysstat (
  # Class parameters are populated from module hiera data
  String $package,
  String $cron_path,
  String $cron_path2,
  String $conf_path,
  String $sa1_path,
  String $sa2_path,
  String $sa2_hour,
  String $sa2_minute,
  String $sa_dir,

  # Class parameters are populated from External(hiera)/Defaults/Fail
  String    $sa1_options      = '-S ALL',
  Integer   $interval         = 2,
  Integer   $sa1_interval     = $interval,
  Integer   $duration         = 2,
  Integer   $sa1_duration     = $duration,
  Integer   $samples          = 1,
  Integer   $sa1_samples      = $samples,
  String    $sa2_options      = '-A',
  Integer   $history          = 10,
  Integer   $compressafter    = 31,
  String    $sadc_options     = '-S DISK',
  String    $zip              = 'bzip2',
  String    $generate_summary = 'yes',
  String    $disable          = 'no',
  Integer   $sa2_delay_range  = 0,
  String    $sa_umask         = '0022',
) {
  # Convert duration to seconds
  $sa1_duration_seconds = $sa1_duration * 60 - 1

  if $generate_summary == 'yes' and $disable != 'yes' {
    $svc_summary_ensure = true
  } else {
    $svc_summary_ensure = false
  }

  if $disable == 'yes' {
    $file_ensure        = 'absent'
    $cron_ensure        = 'absent'
    $svc_collect_ensure = false
  } else {
    $file_ensure        = 'file'
    $cron_ensure        = 'present'
    $svc_collect_ensure = true
  }

  case $facts['os']['family'] {
    'AIX': {
      cron { 'sa1_path_weekday':
        ensure  => 'absent',
        command => "${sa1_path} 1200 3 &",
        user    => 'adm',
        hour    => ['8-17'],
        minute  => [0],
        weekday => ['1-5'],
      }
      cron { 'sa1_path_weekday_after_hours':
        ensure  => 'absent',
        command => "${sa1_path} &",
        user    => 'adm',
        minute  => [0],
        hour    => ['18-7'],
        weekday => ['1-5'],
      }
      cron { 'sa1_path_weekend':
        ensure  => 'absent',
        command => "${sa1_path} &",
        user    => 'adm',
        minute  => [0],
        weekday => [0,6],
      }
      cron { 'sa2_path_weekday_after_hours':
        ensure  => $cron_ensure,
        command => "${sa2_path} -s 8:00 -e 18:01 -i 3600 -ubcwyaqvm &",
        user    => 'adm',
        minute  => [5],
        hour    => [18],
        weekday => ['1-5'],
      }
      cron { 'sa1_daily_5_mins':
        ensure  => $cron_ensure,
        command => "${sa1_path} &",
        user    => 'adm',
        minute  => [0,5,10,15,20,25,30,35,40,45,50,55],
        weekday => ['0-6'],
      }
    }
    default: {
      package { $package:
        ensure => 'installed',
      }

      if ($facts['os']['family'] == 'RedHat' and Float($facts['os']['release']['major']) >= 8.0)
      or ($facts['os']['distro'] and $facts['os']['distro']['id'] == 'Debian' and Float($facts['os']['release']['major']) >= 11.0 )
      or ($facts['os']['distro'] and $facts['os']['distro']['id'] == 'Ubuntu' and Float($facts['os']['release']['major']) >= 22.04) {
        file { [
            '/etc/systemd/system/sysstat-summary.timer.d',
            '/etc/systemd/system/sysstat-collect.timer.d',
            '/etc/systemd/system/sysstat-summary.service.d',
            '/etc/systemd/system/sysstat-collect.service.d',
          ]:
            ensure => 'directory',
            mode   => '0755',
            group  => 'root',
            owner  => 'root',
        }
        exec { 'systemctl daemon-reload':
          command     => 'systemctl daemon-reload',
          path        => ['/bin','/usr/bin','/sbin','/usr/sbin'],
          refreshonly => true,
          subscribe   => Package[$package],
        }
        file { '/etc/systemd/system/sysstat-collect.timer.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_collect.timer.override.epp', {
              sa1_interval => $sa1_interval,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        file { '/etc/systemd/system/sysstat-summary.timer.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_summary.timer.override.epp', {
              sa2_minute => $sa2_minute,
              sa2_hour   => $sa2_hour,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        file { '/etc/systemd/system/sysstat-collect.service.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_collect.service.override.epp', {
              sa1_path             => $sa1_path,
              sa1_duration_seconds => $sa1_duration_seconds,
              sa1_samples          => $sa1_samples,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        file { '/etc/systemd/system/sysstat-summary.service.d/override.conf':
          ensure  => file,
          content => epp('sysstat/sysstat_summary.service.override.epp', {
              sa2_path    => $sa2_path,
              sa2_options => $sa2_options,
          }),
          notify  => Exec['systemctl daemon-reload'],
        }
        service { 'sysstat-collect.timer':
          ensure  => $svc_collect_ensure,
          enable  => $svc_collect_ensure,
          require => Package[$package],
        }
        service { 'sysstat-summary.timer':
          ensure  => $svc_summary_ensure,
          enable  => $svc_summary_ensure,
          require => Package[$package],
        }
      } else {
        file { $cron_path:
          ensure  => $file_ensure,
          content => epp('sysstat/crontab.epp', {
              sa1_path             => $sa1_path,
              sa1_options          => $sa1_options,
              sa1_interval         => $sa1_interval,
              sa1_duration         => $sa1_duration,
              sa1_duration_seconds => $sa1_duration_seconds,
              sa1_samples          => $sa1_samples,
              sa2_path             => $sa2_path,
              sa2_options          => $sa2_options,
              sa2_minute           => $sa2_minute,
              sa2_hour             => $sa2_hour,
              generate_summary     => $generate_summary,
          }),
        }
      }

      file { $conf_path:
        ensure  => file,
        content => epp('sysstat/sysconfig.epp', {
            history         => $history,
            compressafter   => $compressafter,
            sa_dir          => $sa_dir,
            sa2_delay_range => $sa2_delay_range,
            sadc_options    => $sadc_options,
            sa_umask        => $sa_umask,
            zip             => $zip,
        }),
        require => Package[$package],
      }

      file { $sa_dir:
        ensure => directory,
        owner  => 'root',
        group  => 'root',
      }

      # With this module we disable the Debian uniqueness regardless of whether
      # the module is disabled or not
      if $facts['os']['family'] == 'Debian' {
        service { 'sysstat':
          ensure => false,
          enable => $svc_collect_ensure,
        }
        file { $cron_path2:
          ensure => absent,
        }
      }
    }
  }
}
