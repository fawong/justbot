require 'rspec'
module Justbot
  # a user's session. Can store per-plugin data using {Session#storage}
  class Session
    # session duration time: 24 hours
    DURATION = (24 * 60 * 60)

    # container of all active sessions
    @sessions = {}

    # occurs when someone tries to confirm a session in an incorrect manner,
    # either by confirming when not required, or by incorrectly confirming
    class SessionConfirmationError < Exception
      def to_s
        "Confirmation key incorrect"
      end
    end

    # internal class to store plugin-user-session data
    class SessionStorage
      # create a new one.
      def initialize
        @storage = {}
      end

      # Return the session storage for a plugin.
      # plugins should only use this storage method if they require users to be authenticated.
      # @see #access_symbol for parameter information
      # @example
      #   my_plugin_user_data = Session.for(m.user.mask).storage[self]
      def [](key)
        @storage[access_symbol(key)]
      end

      # set the plugin storage to value
      # @see #access_symbol for parameter information
      def []=(key, value)
        @storage[access_symbol(key)] = value
      end

      # return all plugin data for this session
      # @return [Hash{Symbol => Any}]
      def all
        @storage
      end

      private

      # storage access hashing filter
      # @param [String, Symbol, Chinch::Plugin] v the storage key
      #   v is usually an instance of Cinch::Plugin, but can also be a normal
      #   symbol identifier. Strings are converted to thier symbolic equivalent.
      def access_symbol(v)
        if v.is_a? String
          v.to_sym
        elsif v.is_a? Symbol
          v
        else
          v.class.name.to_sym
        end
      end
    end


    # find a session for the given mask
    # @param [Cinch::Message, Cinch::User, String] m a mask, or a Cinch user-like class
    # @return [Session, nil] session for that mask, or nil if there's no session for that mask.
    def self.for(m)
      m = m.user.mask if m.is_a? Cinch::Message
      m = m.mask if m.is_a? Cinch::User
      @sessions[m.to_s]
    end

    # move a session from one mask to another
    def self.migrate(old_mask, new_mask)
      @sessions[new_mask] = @sessions.delete(old_mask)
    end

    # return the hash of all sessions
    # @return [Hash{String => Session}]
    def self.all
      @sessions
    end

    ###### instance methods

    # create a new session
    # @param user [Justbot::Models::User] attatch this user to the session
    # @param mask [String, Cinch::Mask] the IRC mask of the user
    def initialize(user, mask)
      mask = mask.to_s
      @user = user
      @mask = mask.to_s
      @storage = SessionStorage.new

      @expiration = nil

      # put this into the global sessions map
      self.class.all[mask] = self
    end



    # the user for the session. useful for {Justbot::User#is_admin?}
    attr_reader   :user

    # session IRC mask
    attr_reader   :mask

    # access session storage data
    attr_reader   :storage

    # when the session expires.
    attr_reader   :expiration



    # start the session by setting its expiration
    def start
      @expiration = Time.now + DURATION
    end

    # is this session currently active?
    # used to determine if the session is valid in time
    def active?
      (not @expiration.nil?) and
          Time.now < @expiration
    end

    # can this session issue commands as @user?
    def authed?
      active? && @confirmed
    end

    # change the session mask
    # database session data must be handled elsewhere
    def mask=(new_mask)
      new_mask = new_mask.to_s
      self.class.migrate(@mask, new_mask)
      @mask = new_mask
    end

    # end the session now so that #active? will return false
    # and remove the session from the session list
    def stop!
      self.class.all.delete(self.mask)
    end
  end

  # tests!
  describe Session do
    it "retrieves sessions via mask" do
      mask = Session.random_secret + ' mask'
      s = Session.new('dummy user value', mask)
      retrieved = Session.for(mask)
      retrieved.should eq(s)
    end

    describe "#active?" do
      it "returns false on newly-created sessions" do
        s = Session.new('value', 'testing mask')
        s.active?.should eq(false)
      end

      it "returns true on sessions that have just started" do
        s = Session.new('value', 'testing mask')
        s.start
        s.active?.should eq(true)
      end

      it "returns false on sessions older than Session::DURATION" do
        old_duration = Session::DURATION
        s = Session.new('value', 'testing mask')
        # temporarily change duration so we don't have to wait X hours
        old_duration, Session::DURATION = Session::DURATION, 15
        s.start
        Session::DURATION = old_duration
        sleep 20
        s.active?.should eq(false)
      end
    end

    describe "#storage" do
      it "is different for different session objects, even for same mask" do
        s1 = Session.new('user', 'mask')
        s2 = Session.new('user', 'mask')
        (s1.storage.equal? s2.storage).should be_false
      end

      it "stores and retrieves values for string keys" do
        s = Session.new('user', 'testing mask')
        s.storage['key'] = 'value'
        s.storage['key'].should eq('value')
      end

      it "stores and retrieves values for object instances" do
        s = Session.new('user', 'testing mask')
        obj = Array.new
        s.storage[obj] = 'value'
        s.storage[obj].should eq('value')
      end

      it "retrieves the same value for different instances of a class" do
        class Example; end
        obj1 = Example.new
        obj2 = Example.new
        s = Session.new('user', 'testing mask')
        s.storage[obj1] = 'value'
        s.storage[obj2].should eq('value')
      end
    end

    describe "#mask=" do
      it "changes mask identity in the class itself" do
        s = Session.new('value', 'old mask')
        s.mask = 'new mask'
        Session.for('new mask').should eq(s)
      end
    end

  end
end
