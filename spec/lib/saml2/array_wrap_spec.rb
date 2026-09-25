# frozen_string_literal: true

require "open3"
require "rbconfig"

module SAML2
  describe ArrayWrap do
    describe ".wrap" do
      it "returns an empty array for nil" do
        expect(ArrayWrap.wrap(nil)).to eql []
      end

      it "returns the same array for an array" do
        array = [1, 2]
        expect(ArrayWrap.wrap(array)).to equal array
      end

      it "wraps a scalar" do
        expect(ArrayWrap.wrap("a")).to eql ["a"]
      end

      it "wraps a hash instead of converting it to pairs" do
        hash = { a: 1 }
        expect(ArrayWrap.wrap(hash)).to eql [hash]
      end

      it "wraps a Set instead of enumerating it" do
        set = Set[1, 2]
        expect(ArrayWrap.wrap(set)).to eql [set]
      end

      it "wraps a Range instead of enumerating it" do
        expect(ArrayWrap.wrap(1..3)).to eql [1..3]
      end

      it "uses to_ary when available" do
        object = Object.new
        def object.to_ary
          [:converted]
        end
        expect(ArrayWrap.wrap(object)).to eql [:converted]
      end

      it "wraps an object whose to_ary returns nil" do
        object = Object.new
        def object.to_ary
          nil
        end
        expect(ArrayWrap.wrap(object)).to eql [object]
      end
    end

    describe "when required in isolation" do
      def run_isolated(script)
        lib = File.expand_path("../../../lib", __dir__)
        Open3.capture2e(RbConfig.ruby, "-I", lib, "-e", script)
      end

      it "is available to SAML2::Status" do
        output, status = run_isolated(<<~RUBY)
          require "saml2/status"
          status = SAML2::Status.new
          status.codes = SAML2::Status::SUCCESS
          raise "unexpected codes" unless status.codes == [SAML2::Status::SUCCESS]
        RUBY
        expect(status).to be_success, output
      end

      it "is available to SAML2::Subject" do
        output, status = run_isolated(<<~RUBY)
          require "saml2/subject"
          subject = SAML2::Subject.new
          confirmation = SAML2::Subject::Confirmation.new
          subject.confirmations = confirmation
          raise "unexpected confirmation" unless subject.confirmation.equal?(confirmation)
        RUBY
        expect(status).to be_success, output
      end
    end
  end
end
