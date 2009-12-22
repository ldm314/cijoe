# Include hook code here

require 'net/smtp'
require 'timeout'

begin
  require 'openssl'
rescue LoadError
end

Net::SMTP.class_eval do

  alias_method :old_initialize, :initialize
  def initialize(*args)
    @usetls = @@usetls
    old_initialize *args
  end

  @@usetls = false

  def self.enable_tls()
    @@usetls = true
  end

  def self.disable_tls()
    @@usetls = false
  end

  def self.use_tls?()
    @@usetls
  end

  def use_tls?()
    @usetls
  end

  def enable_tls()
    print "tls enabled\n"
    @usetls = true
  end

  def disable_tls()
    @usetls = false
  end

  def use_tls?()
    @usetls
  end

  private
  def do_start(helodomain, user, secret, authtype)
    raise IOError 'SMTP session already started' if @started
    if user or secret
      check_auth_method(authtype || DEFAULT_AUTH_TYPE)
      check_auth_args user, secret
    end

    sock = timeout(@open_timeout) {TCPSocket.open(@address, @port) }
    @socket = Net::InternetMessageIO.new(sock)
    @socket.read_timeout = @read_timeout

    check_response(critical {recv_response() } )
    do_helo(helodomain)

    if @usetls 
      raise 'openssl is not installed' unless defined?(OpenSSL)
      ssl = OpenSSL::SSL::SSLSocket.new(sock)
      starttls
      ssl.sync_close = true
      ssl.connect

      @socket = Net::InternetMessageIO.new(ssl)
      @socket.read_timeout = @read_timeout
      do_helo(helodomain)
    end

    authenticate user, secret, authtype if user
    @started = true
  ensure
    @socket.close if not @started and @socket and not @socket.closed?
  end

  def do_helo(helodomain)
    begin
      if @esmtp
        ehlo helodomain
      else
        helo helodomain
      end
    rescue Net::ProtocolError
      if @esmtp
        @esmtp = false
        @error_occured = false
        retry
      end
      raise
    end
  end

  def starttls
    getok('STARTTLS')
  end

  def quit
    begin
      getok('QUIT')
    rescue EOFError
      # gmail sucks
    end
  end
end