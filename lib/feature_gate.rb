class FeatureGate

  attr_accessor :name

  attr_accessor :value

  attr_accessor :rule_id

  attr_accessor :group_name

  attr_accessor :id_type

  attr_accessor :evaluation_details

  attr_accessor :target_app_ids

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
