require File.dirname(__FILE__) + '/../mmmail'

class CIJoe
  module Email
    def self.activate
      if valid_config?
        CIJoe::Build.class_eval do
          include CIJoe::Email
        end

        puts "Loaded Email notifier"
      else
        puts "Can't load Email notifier."
        puts "Please add the following to your project's .git/config:"
        puts "[email]"
        puts "\tto = build@example.com"
        puts "\tuser = horst"
        puts "\tpass = passw0rd"
        puts "\thost = mail.example.com"
        puts "\tauthtype = plain"
        puts "\tenabletls = 1"
      end
    end

    def self.config
      @config ||= {
        :to        => Config.email.to.to_s, 
        :user      => Config.email.user.to_s,
        :pass      => Config.email.pass.to_s,
        :host      => Config.email.host.to_s,
        :auth_type => Config.email.authtype.to_s,
        :enable_tls => Config.email.enabletls.to_s
      }
    end

    def self.valid_config?
      %w( host user pass to auth_type ).all? do |key|
        !config[key.intern].empty?
      end
    end

    def notify
      options = {
        :to => Email.config[:to],
        :from => Email.config[:to],
        :subject => "(#{project}) Build failed",
        :body => mail_body
      }
      MmMail.mail(options, mail_config) if failed?
    end

    def mail_config
      config = MmMail::Transport::Config.new
      config.auth_user = Email.config[:user]
      config.auth_pass = Email.config[:pass]
      config.auth_type = Email.config[:auth_type].to_sym
      config.host = Email.config[:host]
      config.enable_tls = Email.config[:enable_tls] == "1" ? true : false
      config
    end
    
    def mail_body
      "The commit '#{commit.message}' (#{commit.url}) by #{commit.author} caused the build to fail."
    end
  end
end
