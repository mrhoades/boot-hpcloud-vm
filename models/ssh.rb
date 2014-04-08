require 'net/ssh/simple'
require 'net/ssh'

class SshSimple
  attr_accessor :os_username,
                :os_password,
                :os_tenant_name,
                :os_auth_url,
                :os_region_name,
                :os_availability_zone

  def initialize(build, listener, vars_in)

    @logger = listener
    @build = build
    @env = build.native.getEnvironment
    @vars = vars_in

    Net::SSH.start('15.185.190.19','ubuntu', {}) do |ssh|
      result = ssh.exec! "echo $PS1 && export myuser=matty && echo $myuser"
      @logger.info result
      result = ssh.exec! "sudo apt-get update"
      @logger.info result
      result = ssh.exec! "echo $myuser"
      @logger.info result

      #result = ssh.exec "echo $PS1,export myuser=matty && echo $myuser,sudo apt-get update,ls -al,echo $PS2,echo $myuser".split(',')
      #result = ssh_exec! ssh, "/bin/bash, ls -al,ls -al,sudo apt-get update".split(',')


    end

  rescue Timeout::Error => e
    write_log e
  rescue Exception => e
    write_log e
  ensure
    begin

    end
  end

  # Create and re-use one instance per thread, with a default username.
  def ss
    Thread.current[:simplessh] ||= Net::SSH::Simple.new({:user => 'ubuntu'})
  end

  # Strictly optional. You may use this method to close the
  # SSH connections early. Otherwise our instance will tear
  # down automatically when the enclosing thread finishes.
  def ss_close
    ss.close
    Thread.current[:simplessh] = nil
  end

  def ssh_exec!(ssh, command_array)
    stdout_data = ""
    stderr_data = ""
    exit_code = nil
    exit_signal = nil

    command_array.each do |command|

      ssh.open_channel do |channel|

        @logger.info "SEND COMMAND: #{command}"

        channel.exec(command) do |ch, success|
          unless success
            abort "FAILED: couldn't execute command (ssh.channel.exec)"
          end

          channel.on_data do |ch,data|
            @logger.info data.chomp
          end

          channel.on_extended_data do |ch,type,data|
            @logger.info data.chomp
          end

          channel.on_request("exit-status") do |ch,data|
            @logger.info 'EXIT SIGNAL:'
            @logger.info data
          end

          channel.on_request("exit-signal") do |ch, data|
            @logger.info 'EXIT STATUS:'
            @logger.info data
          end

        end

        # want for prompt
        @logger.info "WAIT FOR PROMPT: #{command}"

        channel.wait

      end

      ssh.loop

    end


    [stdout_data, stderr_data, exit_code, exit_signal]
  end








  def do_something_involving_ssh

    @logger.info('do something yo.......')

    #ss.ssh(host='15.185.190.19',cmd="/bin/bash && ls -al && echo 'whatwhatwhat' && export MYNAME=mattyj && echo $MYNAME",{:user => 'ubuntu'})
    #ss.ssh(host='15.185.190.19',cmd='echo "Hello World.Hello World.Hello World.Hello World."',{:user => 'ubuntu'})
    #ss.ssh(host='15.185.190.19',cmd='echo $MYNAME && echo $MYNAME && echo $MYNAME"',{:user => 'ubuntu'})
    #
    #print result


    Net::SSH::Simple.sync do

      result = ss.ssh(host='15.185.190.19',cmd='/bin/bash',{:user => 'ubuntu'}) do |e,c,d|
        case e
          when :start
            @logger.info 'IN START.....\n'
            c.send_data "ls -al && echo 'whatwhatwhat' && export MYNAME=mattyj && echo $MYNAME"
            c.eof!
          when :stdout
          (@buf ||= '') << d
            while line = @buf.slice!(/(.*)\r?\n/)
              @logger.info line.chomp
            end
          when :stderr
            # read the input line-wise (it *will* arrive fragmented!)
            (@buf ||= '') << d
            while line = @buf.slice!(/(.*)\r?\n/)
              @logger.info line.chomp
            end

        end
      end

      @logger.info result
    end
  end


  def connect_session
    @logger.info 'connect session'
    @session = Net::SSH.start(host='15.185.190.19',user='ubuntu', options={})
    run_cmd('/bin/bash && ls -al')
    @session.loop
  end

  def run_cmd(cmd_in)
    @logger.info 'connect session'
    @session.open_channel do |channel|
      channel.on_data do |ch, data|
        @logger.info "#{data}"
      end
      channel.exec cmd_in
    end
  end

  def do_something_involving_ssh2

    @logger.info('do something yo 2.......')

    # capture all stderr and stdout output from a remote process
    output = @session.exec!("hostname")

    @logger.info output

    # capture only stdout matching a particular pattern
    stdout = ''
    @session.exec!("ls -l && echo 'hello baby bitches..'") do |channel, stream, data|
      stdout << data if stream == :stdout
    end
    @logger.info stdout

    # run multiple processes in parallel to completion
    @session.exec "sed ..."
    @session.exec "awk ..."
    @session.exec "rm -rf ..."

    # open a new channel and configure a minimal set of callbacks, then run
    # the event loop until the channel finishes (closes)
    channel = @session.open_channel do |ch|
      ch.exec "ls -al" do |ch, success|
        raise "could not execute command" unless success

        # "on_data" is called when the process writes something to stdout
        ch.on_data do |c, data|
          @logger.info data
        end

        # "on_extended_data" is called when the process writes something to stderr
        ch.on_extended_data do |c, type, data|
          @logger.info data
        end

        ch.on_close {
          @logger.info 'FIRED ON CLOSE'
        }
      end

    channel.wait
    end

    @logger.info 'DONEEEEEEEEE'

  end


  def write_log(obj_in)
    @logger.info ' '
    @logger.info obj_in.to_s
    @logger.info ' '
  end
end