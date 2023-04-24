module DefaultHostgroupBaseHostPatch
  extend ActiveSupport::Concern

  module ManagedOverrides
    # rubocop:disable Lint/UnusedMethodArgument
    def import_facts(facts, source_proxy = nil, without_alias = false)
      # rubocop:enable Lint/UnusedMethodArgument
      super(facts, source_proxy)
    end
  end

  module Overrides
    # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
    def import_facts(facts, source_proxy = nil, without_alias = false)
      # rubocop:enable Metrics/AbcSize,Metrics/CyclomaticComplexity

      # Load the facts anyway, hook onto the end of it
      result = super(facts, source_proxy)

      # Module#prepend removes the import_facts_without_match_hostgroup method, so use
      # a flag to return here if needed
      return result if without_alias

      # Check settings are created
      return result unless settings_exist?

      Rails.logger.debug "DefaultHostgroupMatch: performing Hostgroup match for #{self.host}"

      return result unless host_new_or_forced?
      return result unless host_has_no_hostgroup_or_forced?

      facts_map = SETTINGS[:default_hostgroup][:facts_map]
      new_hostgroup = find_match(facts_map)

      return result unless new_hostgroup

      self.host.hostgroup = new_hostgroup
      self.host.environment = new_hostgroup.environment if Setting[:force_host_environment] == true and facts[:_type] == :puppet
      self.host.save(validate: false)
      Rails.logger.info "DefaultHostgroupMatch: #{facts["hostname"]} added to #{new_hostgroup}"

      result
    end
  end

  included do
    prepend Overrides
  end

  def find_match(facts_map)
    facts_map.each do |group_name, facts|
      hg = Hostgroup.find_by(title: group_name)
      return hg if hg.present? && group_matches?(facts)
    end
    Rails.logger.info "No match ..."
    false
  end

  def group_matches?(facts)
    facts.each do |fact_name, fact_regex|
      fact_regex.gsub!(%r{(\A/|/\z)}, "")
      host_fact_value = self.host.facts[fact_name]
      match_fact_value = Regexp.new(fact_regex).match?(host_fact_value)
      Rails.logger.info "DefaultHostgroupMatch: Host=#{self.host} Fact=#{fact_name} Value=#{host_fact_value} Regex=#{fact_regex} Match?=#{match_fact_value}"
      return true if match_fact_value
    end
    false
  end

  def settings_exist?
    unless SETTINGS[:default_hostgroup] && SETTINGS[:default_hostgroup][:facts_map]
      Rails.logger.warn "DefaultHostgroupMatch: Could not load :default_hostgroup map from Settings."
      return false
    end
    true
  end

  def host_new_or_forced?
    if Setting[:force_hostgroup_match_only_new]
      # hosts have already been saved during import_host, so test the creation age instead
      new_host = ((Time.current - self.host.created_at) < 300)
      unless new_host && self.host.hostgroup.nil? && self.host.reports.empty?
        Rails.logger.debug "DefaultHostgroupMatch: skipping #{self.host}, host exists"
        return false
      end
    end
    true
  end

  def host_has_no_hostgroup_or_forced?
    unless Setting[:force_hostgroup_match]
      if self.host.hostgroup.present?
        Rails.logger.debug "DefaultHostgroupMatch: skipping, host #{self.host} has hostgroup"
        return false
      end
    end
    true
  end
end
