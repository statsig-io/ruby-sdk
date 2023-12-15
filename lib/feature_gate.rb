# typed: false

require 'sorbet-runtime'

class FeatureGate
  extend T::Sig

  sig { returns(String) }
  attr_accessor :name

  sig { returns(T::Boolean) }
  attr_accessor :value

  sig { returns(String) }
  attr_accessor :rule_id

  sig { returns(T.nilable(String)) }
  attr_accessor :group_name

  sig { returns(String) }
  attr_accessor :id_type

  sig { returns(T.nilable(Statsig::EvaluationDetails)) }
  attr_accessor :evaluation_details

  sig { returns(T.nilable(T::Array[String])) }
  attr_accessor :target_app_ids

  sig do
    params(
      name: String,
      value: T::Boolean,
      rule_id: String,
      group_name: T.nilable(String),
      id_type: String,
      evaluation_details: T.nilable(Statsig::EvaluationDetails),
      target_app_ids: T.nilable(T::Array[String])
    ).void
  end
  def initialize(
    name,
    value: false,
    rule_id: '',
    group_name: nil,
    id_type: '',
    evaluation_details: nil,
    target_app_ids: nil
  )
    @name = name
    @value = value
    @rule_id = rule_id
    @group_name = group_name
    @id_type = id_type
    @evaluation_details = evaluation_details
    @target_app_ids = target_app_ids
  end

  sig { params(res: Statsig::ConfigResult).returns(FeatureGate) }
  def self.from_config_result(res)
    new(
      res.name,
      value: res.gate_value,
      rule_id: res.rule_id,
      group_name: res.group_name,
      id_type: res.id_type,
      evaluation_details: res.evaluation_details,
      target_app_ids: res.target_app_ids
    )
  end
end
