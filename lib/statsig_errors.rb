module Statsig
  class UninitializedError < StandardError
    def initialize(msg="Must call initialize first.")
      super
    end
  end

  class ValueError < StandardError

  end
end
