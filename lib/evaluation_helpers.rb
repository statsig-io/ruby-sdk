require 'time'

module EvaluationHelpers
  def self.compare_numbers(a, b, func)
    return false unless self.is_numeric(a) && self.is_numeric(b)
    func.call(a.to_f, b.to_f) rescue false
  end

  # returns true if array contains value, ignoring case when comparing strings
  def self.array_contains(array, value)
    return false unless array.is_a?(Array) && !value.nil?
    return array.include?(value) unless value.is_a?(String)
    array.any?{ |s| s.is_a?(String) && s.casecmp?(value) } rescue false
  end

  # returns true if array has any element that evaluates to true with value using func lambda, ignoring case
  def self.match_string_in_array(array, value, func)
    return false unless array.is_a?(Array) && value.is_a?(String)
    array.any?{ |s| s.is_a?(String) && func.call(value.downcase, s.downcase) } rescue false
  end

  def self.compare_times(a, b, func)
    begin
      time_1 = self.get_epoch_time(a)
      time_2 = self.get_epoch_time(b)
      func.call(time_1, time_2)
    rescue
      false
    end
  end

  private

  def self.is_numeric(v)
    !(v.to_s =~ /\A[-+]?\d*\.?\d+\z/).nil?
  end

  def self.get_epoch_time(v)
    time = self.is_numeric(v) ? Time.at(v.to_f) : Time.parse(v)
    if time.year > Time.now.year + 100
      # divide by 1000 when the epoch time is in milliseconds instead of seconds
      return time.to_i / 1000
    end
    return time.to_i
  end
end