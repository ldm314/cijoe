require File.dirname(__FILE__) + '/../lib/cijoe'
require 'ostruct'

describe CIJoe::Email do
  
  describe "activate" do
    it "should include Email into the Build class if the config is valid" do
      CIJoe::Config.stub!(:email => stub(:to => 'build@housetrip.com', :user => 'joe', :pass => 'passwd', :host => 'mail.example.com'))
      
      CIJoe::Email.activate
      CIJoe::Build.ancestors.should include(CIJoe::Email)
    end
    
    it "should not include Email into the Build class if the config is not valid" do
      CIJoe::Email.activate
      CIJoe::Build.ancestors.should_not include(CIJoe::Email)
    end
  end
  
  
  describe "notify" do
    class TestBuild
      include CIJoe::Email

      def initialize(worked)
        @worked = worked
      end

      def worked?
        @worked
      end

      def failed?
        !@worked
      end

      def commit
        OpenStruct.new(:url => "github.com/commit/bha75as")
      end
    end

    CIJoe::Config.class_eval do
      def self.email
        OpenStruct.new(
          :to => 'build@housetrip.com'
        )
      end
    end
    
    it "should send an email if the build failed" do
      MmMail.should_receive(:send).with(:to => 'build@housetrip.com', :from => 'build@housetrip.com', :subject => 'Build failed', :body => 'The commit github.com/commit/bha75as caused the build to fail.')
      TestBuild.new(false).notify
    end
    
    it "should send no email if the build succeeded" do
      MmMail.should_not_receive(:send)
      TestBuild.new(true).notify
    end
  end
end