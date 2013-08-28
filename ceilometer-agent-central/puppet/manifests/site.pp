apt::conf { 'proxy':
  #content => 'Acquire::http::Proxy "http://wheezyj:3142";'
  content => 'Acquire::http::Proxy "http://andouille:3142";'
}

apt::source { 'havana':
  location => '[trusted=1] ftp://havana.pkgs.enovance.com/debian',
  release  => 'havana',
  repos    => 'main',
}

apt::source { 'havana-backports':
  location => '[trusted=1] http://ftparchive.gplhost.com/debian',
  release  => 'havana-backports',
  repos    => 'main'
}

Apt::Conf<||> -> Apt::Source<||> -> Package<||>

# Install rabbitmq else ceilometer-agent-central won't start …

class { 'rabbitmq::server':
  config_cluster           => true,
  cluster_disk_nodes       => ['central0', 'central1'],
  wipe_db_on_cookie_change => true,
}

# The central agent requires a keystone service to start, dammit!

class { 'keystone':
  verbose      => true,
  debug        => true,
  catalog_type => 'sql',
  admin_token  => 'admin_token',
}
class { 'keystone::roles::admin':
  email    => 'example@abc.com',
  password => 'ChangeMe',
}

# Now we can install ceilometer-agent-central

Exec {
  path => ['/usr/bin', '/bin', '/usr/sbin', '/sbin']
}

class { 'ceilometer':
  metering_secret => 'darksecret'
}

class { 'ceilometer::agent::central':
  enabled          => false,
  auth_user        => 'admin',
  auth_password    => 'ChangeMe',
  auth_tenant_name => 'openstack',
}

# And finally corosync/pacemaker

class { 'corosync':
  enable_secauth    => false,
  # authkey         => '/var/lib/puppet/ssl/certs/ca.pem',
  bind_address      => $::network_eth0,
  multicast_address => '239.1.1.2',
}

cs_property {
  'no-quorum-policy':         value => 'ignore';
  'stonith-enabled':          value => 'false';
  'pe-warn-series-max':       value => 1000;
  'pe-input-series-max':      value => 1000;
  'cluster-recheck-interval': value => '5min';
}

Service['keystone'] -> Service['corosync']

corosync::service { 'pacemaker':
  version => '0',
}

Package['corosync'] ->
file { '/usr/lib/ocf/resource.d/heartbeat/ceilometer-agent-central':
  source  => '/vagrant/ceilometer-agent-central_resource-agent',
  mode    => '0755',
  owner   => 'root',
  group   => 'root',
} ->
cs_primitive { 'ceilometer-agent-central':
  primitive_class => 'ocf',
  primitive_type  => 'ceilometer-agent-central',
  provided_by     => 'heartbeat',
  operations      => {
    'monitor' => { interval => '10s', 'timeout' => '30s' },
    'start'   => { interval => '0', 'timeout' => '30s', 'on-fail' => 'restart' }
  }
}
