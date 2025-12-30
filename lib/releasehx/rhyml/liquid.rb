# frozen_string_literal: true

module ReleaseHx
  module RHYML
    module RHYMLFilters
      def pasterize input
        return input unless input.is_a? String

        RHYML.pasterize(input)
      end
    end
  end
end
