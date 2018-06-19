#!/usr/bin/env python3
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.
#

import getopt
import sys
import base64

from winrm import protocol


AUTH_BASIC = "basic"
AUTH_KERBEROS = "kerberos"
AUTH_CERTIFICATE = "certificate"

DEFAULT_PORT_HTTP = 5985
DEFAULT_PORT_HTTPS = 5986


def print_usage():
    print("%s [-U <url>] [-H <host>] [-P <port>] [-s] "
          "[-a <basic|kerberos|certificate>] "
          "[-u <username>] [-p <password>] "
          "[-c <client_cert_pem> -k <client_cert_cert_key_pem>] "
          "--file <powershell_script> --powershell <cmd> [cmd_args]" % sys.argv[0])


def parse_args():
    args_ok = False
    auth = AUTH_BASIC
    username = None
    password = None
    url = None
    host = None
    port = None
    use_ssl = False
    cmd = None
    cert_pem = None
    cert_key_pem = None
    is_powershell_cmd = False
    is_powershell_script = False
    try:
        show_usage = False
        opts, args = getopt.getopt(sys.argv[1:], "hsU:H:P:u:p:c:k:a:",
                                   ["powershell", "file"])
        for opt, arg in opts:
            if opt == "-h":
                show_usage = True
            if opt == "-s":
                use_ssl = True
            if opt == "-H":
                host = arg
            if opt == "-P":
                port = arg
            if opt == "-U":
                url = arg
            elif opt == "-a":
                auth = arg
            elif opt == "-u":
                username = arg
            elif opt == "-p":
                password = arg
            elif opt == "-c":
                cert_pem = arg
            elif opt == "-k":
                cert_key_pem = arg
            elif opt == "--powershell":
                is_powershell_cmd = True
            elif opt == "--file":
                is_powershell_script = True
        if is_powershell_cmd and not is_powershell_script:
            cmd = args
        elif is_powershell_script:
            with open(args[0], 'r') as script_file:
                content = script_file.read()
            cmd = content.replace('\n', '; ')
        if (show_usage or not
                (cmd and
                 (url and not host and not port and not use_ssl) or
                 host and ((bool(port) ^ bool(use_ssl) or
                            not port and not use_ssl)) and
                 (auth == AUTH_BASIC and username and password or
                  auth == AUTH_CERTIFICATE and cert_pem and cert_key_pem or
                  auth == AUTH_KERBEROS))):
            print_usage()
        else:
            args_ok = True
    except getopt.GetoptError:
        print_usage()
    return (args_ok, url, host, use_ssl, port, auth, username, password,
            cert_pem, cert_key_pem, cmd, is_powershell_cmd, is_powershell_script)


def run_wsman_cmd(url, auth, username, password, cert_pem, cert_key_pem, cmd):
    protocol.Protocol.DEFAULT_TIMEOUT = "PT3600S"
    if not auth:
        auth = AUTH_BASIC
    auth_transport_map = {AUTH_BASIC: 'plaintext',
                          AUTH_KERBEROS: 'kerberos',
                          AUTH_CERTIFICATE: 'ssl'}
    p = protocol.Protocol(endpoint=url,
                          transport=auth_transport_map[auth],
                          server_cert_validation="ignore",
                          username=username,
                          password=password,
                          cert_pem=cert_pem,
                          cert_key_pem=cert_key_pem)
    shell_id = p.open_shell(codepage=65001)
    command_id = p.run_command(shell_id, cmd[0], cmd[1:])
    std_out, std_err, status_code = p.get_command_output(shell_id, command_id)
    p.cleanup_command(shell_id, command_id)
    p.close_shell(shell_id)
    return (std_out, std_err, status_code)


def get_url(url, host, use_ssl, port):
    if url:
        return url
    else:
        if not port:
            if use_ssl:
                port = DEFAULT_PORT_HTTPS
            else:
                port = DEFAULT_PORT_HTTP
        if use_ssl:
            protocol = "https"
        else:
            protocol = "http"
        return ("%(protocol)s://%(host)s:%(port)s/wsman" % locals())


def main():
    exit_code = 1
    (args_ok, url, host, use_ssl, port, auth, username, password,
     cert_pem, cert_key_pem, cmd, is_powershell_cmd, is_powershell_script) = parse_args()
    if args_ok:
        url = get_url(url, host, use_ssl, port)
        if is_powershell_cmd:
            cmd = ["powershell.exe",
                   "-ExecutionPolicy", "RemoteSigned", "-NonInteractive",
                   "-EncodedCommand",
                   base64.b64encode((" ".join(cmd)).encode("utf-16-le"))]
        if is_powershell_script:
            cmd = ["powershell.exe",
                   "-ExecutionPolicy", "RemoteSigned", "-NonInteractive",
                   "-EncodedCommand",
                   base64.b64encode(cmd.encode("utf-16-le"))]
        std_out, std_err, exit_code = run_wsman_cmd(url, auth, username,
                                                    password, cert_pem,
                                                    cert_key_pem, cmd)
        sys.stdout.write(std_out.decode(encoding='UTF-8').strip("\r\n"))
        sys.stderr.write(std_err.decode(encoding='UTF-8').strip("\r\n"))
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
