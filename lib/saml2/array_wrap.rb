# frozen_string_literal: true

module SAML2
  # Internal replacement for ActiveSupport's +Array.wrap+.
  #
  # Unlike +Kernel#Array+ or splatting, this does not call +to_a+, so hashes,
  # ranges and other enumerables are wrapped as a single element.
  module ArrayWrap
    # @param object [Object]
    # @return [Array]
    def self.wrap(object)
      if object.nil?
        []
      elsif object.respond_to?(:to_ary)
        object.to_ary || [object]
      else
        [object]
      end
    end
  end
end
