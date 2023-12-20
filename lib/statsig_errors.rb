# typed: true
module Statsig
  class UninitializedError < StandardError
    def initialize(msg="Must call initialize first.")
      super
    end
  end

  class ValueError < StandardError

  end

  class InvalidSDKKeyResponse < StandardError
    def initialize(msg="Incorrect SDK Key used to generate response.")
      super
    end
  end
end
