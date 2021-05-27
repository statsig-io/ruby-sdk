module EvaluationHelpers
  def self.compare_numbers(a, b, func)
    return false unless self.is_numeric(a) && self.is_numeric(b)
    func.call(a.to_f, b.to_f) rescue false
  end

  # returns true if array contains value, ignoring case when comparing strings
  def self.array_contains(array, value)
    return false unless array.is_a?(Array) && !value.nil?
    return array.include?(value) unless value.is_a?(String)
    array.any?{ |s| s.is_a?(String) && s.casecmp(value) == 0 } rescue false
  end

  # returns true if array has any element that evaluates to true with value using func lambda, ignoring case
  def self.match_string_in_array(array, value, func)
    return false unless array.is_a?(Array) && value.is_a?(String)
    array.any?{ |s| s.is_a?(String) && func.call(value.downcase, s.downcase) } rescue false
  end

  private

  def self.is_numeric(v)
    !(v.to_s =~ /\A[-+]?\d*\.?\d+\z/).nil?
  end
end