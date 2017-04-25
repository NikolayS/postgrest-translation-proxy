#!/usr/bin/env ruby
if (ARGV[0] =~/^-?-h/) || (! File.exists?('setup.yml'))
  puts <<~USAGEBANNER

    Usage:
      copy the file 'setup-example.yml' to 'setup.yml'
      and put there keys for APIs that you have
      and creds for your database access.
    Then start this script.
    If some :use key is 'false' such engine will not be installed.

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
    # @psql = File.open '/tmp/setup-script.sql', 'w'
    [:global, :google, :promt, :bing].each do |engine|
      @psql = IO::popen( [ 'psql', @cfg[:global][:database] ], 'w' )
      self.send( "setup_#{ engine }" ) if @cfg[engine][:use]
      @psql.close
    end

  end

  def setup_global
    puts "\t\t ==== Core features"
    @psql.write @cfg[:global][:script] + "\n"
  end

  def setup_google
    puts "\t\t ==== Setup Google API"
    @psql.write @cfg[:google][:script].gsub( /YOUR_GOOGLE_API_KEY/, @cfg[:google][:api_key] )
                .gsub( /GOOGLE_BEGIN_AT/, @cfg[:google][:begin_at].to_s )
                .gsub( /GOOGLE_END_AT/, @cfg[:google][:end_at].to_s ) + "\n"
  end

  def setup_promt
    puts "\t\t ==== Setup Promt API"
    @psql.write @cfg[:promt][:script].gsub(/YOUR_PROMT_LOGIN/, @cfg[:promt][:login] )
                  .gsub( /YOUR_PROMT_PASSWORD/, @cfg[:promt][:password] )
                  .gsub( /YOUR_PROMT_SERVER_URL/, @cfg[:promt][:server_url] )
                  .gsub( /PROMT_LOGIN_TIMEOUT/, @cfg[:promt][:login_timeout] )
                  .gsub( /PROMT_COOKIE_FILE/, @cfg[:promt][:cookie_file])
                  .gsub( /PROMT_KEY_VALID_FROM/, @cfg[:promt][:valid_from].to_s )
                  .gsub( /PROMT_KEY_VALID_UNTIL/, @cfg[:promt][:valid_until].to_s ) + "\n"
  end

  def setup_bing
    puts "\t\t ==== Setup MS Bing API"
    @psql.write @cfg[:bing][:script].gsub( /YOUR_BING_API_KEY/, @cfg[:bing][:api_key] )
                  .gsub( /BING_TOKEN_EXPIRATION/, @cfg[:bing][:token_expiration] ) + "\n"
  end

end

Setup.new.setup
