#!/usr/bin/env ruby
if (ARGV[0] =~/^-?-h/) || (! File.exists?('setup.yml'))
  puts <<~USAGEBANNER

    Usage:
      copy the file 'setup-example.yml' to 'setup.yml'
      and put there keys for APIs that you have
      and creds for your database access.
    Then start this script.
    If some api_key is 'null' such engine will not be installed.

  USAGEBANNER
  exit
end

require 'yaml'
class Setup
  def setup
    @cfg = YAML.load_file 'setup.yml'
    # Global setup
    [:global, :google, :promt, :bing].each do |engine|
      filename = "install_#{ engine }_core.sql"
      @cfg[engine][:script] = File.read(filename)
        .gsub( ' DBNAME ', " #{ @cfg[:global][:database] } ")
    end
    ENV['PGPASSWORD'] = @cfg[:global][:password] unless @cfg[:global][:password].nil?
    ENV['PGUSER'] = @cfg[:global][:username] unless @cfg[:global][:username].nil?
    @psql = IO::popen("psql #{ @cfg[:global][:database] }", 'w')
    # @psql = File.open '/tmp/setup-script.sql', 'w'
    [:global, :google, :promt, :bing].each do |engine|
      self.send( "setup_#{ engine }" ) if @cfg[engine][:use]
    end
    @psql.close
  end

  def setup_global
    puts 'Core features'
    @psql.puts @cfg[:global][:script]
  end

  def setup_google
    puts "Setup Google API"
    @cfg[:google][:script].gsub! /YOUR_GOOGLE_API_KEY/, @cfg[:google][:api_key]
    @psql.puts @cfg[:google][:script]
  end

  def setup_promt
    puts "Setup Promt API"
    @cfg[:promt][:script].gsub!(/YOUR_PROMT_LOGIN/, @cfg[:promt][:login] )
      .gsub!( /YOUR_PROMT_PASSWORD/, @cfg[:promt][:password] )
      .gsub!( /YOUR_PROMT_SERVER_URL/, @cfg[:promt][:server_url] )
      .gsub!( /PROMT_LOGIN_TIMEOUT/, @cfg[:promt][:login_timeout] )
    @psql.puts @cfg[:promt][:script]
  end

  def setup_bing
    puts "Setup MS Bing API"
    @psql.puts @cfg[:bing][:script]
  end

end

Setup.new.setup
