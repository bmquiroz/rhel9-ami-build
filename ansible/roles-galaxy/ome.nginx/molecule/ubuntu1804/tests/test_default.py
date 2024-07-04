import os
import testinfra.utils.ansible_runner

testinfra_hosts = testinfra.utils.ansible_runner.AnsibleRunner(
    os.environ['MOLECULE_INVENTORY_FILE']).get_hosts('all')


def test_package(host):
    assert host.package('nginx').is_installed


def test_service(host):
    hostname = host.backend.get_hostname()
    if hostname != 'nginx-custom':
        service = host.service('nginx')
        assert service.is_running


def test_configuration(host):
    c = host.file('/etc/nginx/sites-enabled/default')
    assert not c.exists


def test_logrotate(host):
    log = host.file("/etc/logrotate.d/nginx")
    hostname = host.backend.get_hostname()
    if hostname != 'nginx-custom':
        assert log.contains("daily")
        assert log.contains("rotate 366")
    else:
        assert log.contains("weekly")
        assert log.contains("rotate 5")


def test_version(host):
    hostname = host.backend.get_hostname()
    r = host.run('nginx -v')
    assert r.rc == 0
    ver = r.stderr.strip()
    if hostname == 'nginx-custom':
        assert ver.startswith('nginx version: nginx/1.17.')
    else:
        assert ver.startswith('nginx version: nginx/1.16.')
