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
      end
    end

    def self.config
      @config ||= {
        :to        => Config.email.to.to_s, 
        :user      => Config.email.user.to_s,
        :pass      => Config.email.pass.to_s,
        :host      => Config.email.host.to_s
      }
    end

    def self.valid_config?
      %w( host user pass to ).all? do |key|
        !config[key.intern].empty?
      end
    end

    def notify
      options = {
        :to => Email.config[:to],
        :from => Email.config[:to],
        :subject => 'Build failed',
        :body => "The commit #{commit.url} causes the build to fail."
      }
      MmMail.send(options) if failed?
    end

  end
end
