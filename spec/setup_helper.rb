# frozen_string_literal: true

require "#{::Rails.root}/spec/support/seeds"
require './db/table_generators/external_identifiers_table'

$STARTED_AT = DateTime.now.to_i

module SetupHelper
  def self.auto_admin
    admin, = ::UserSupport.create_admin
    admin
  end

  def self.registration_admin
    admin, = ::UserSupport.create_admin('registration')
    admin
  end

  def self.db_name
    ActiveRecord::Base.connection.current_database
  end

  def self.clear_delayed_job
    puts 'Clear delayed_job'

    Delayed::Job.delete_all
  end

  def self.setup_app_dbs
    puts 'Setup app DBs'

    unless ActiveRecord::Base.connection.table_exists?('activity_log_player_info_e_signs')
      # ESign setup
      # Setup the triggers, functions, etc
      sql_files = %w[create_al_table.sql create_ipa_inex_checklist_table.sql]
      sql_source_dir = Rails.root.join('spec', 'fixtures', 'app_configs', 'test_esign_sql')
      SetupHelper.setup_app_db sql_source_dir, sql_files
    end

    unless ActiveRecord::Base.connection.table_exists?('bhs_assignments')
      # ExportApp
      sql_files = %w[1-create_bhs_assignments_external_identifier.sql 2-create_activity_log.sql
                     3-add_notification_triggers.sql 4-add_testmybrain_trigger.sql 5-create_sync_subject_data_aws_db.sql
                     6-grant_roles_access_to_ml_app.sql]
      sql_source_dir = Rails.root.join('spec', 'fixtures', 'app_configs', 'bhs_sql')
      SetupHelper.setup_app_db sql_source_dir, sql_files
    end

    unless ActiveRecord::Base.connection.table_exists?('adders')
      # Export App
      sql_files = %w[1-create_bhs_assignments_external_identifier.sql 2-create_activity_log.sql
                     6-grant_roles_access_to_ml_app.sql create_adders_table.sql]
      sql_source_dir = Rails.root.join('spec', 'fixtures', 'app_configs', 'config_tests_sql')
      SetupHelper.setup_app_db sql_source_dir, sql_files
    end

    unless ActiveRecord::Base.connection.table_exists?('zeus_bulk_message_statuses')
      # Bulk
      # Setup the triggers, functions, etc
      sql_files = %w[test/drop_schema.sql test/create_schema.sql
                     bulk/create_zeus_bulk_messages_table.sql bulk/dup_check_recipients.sql
                     bulk/create_zeus_bulk_message_recipients_table.sql bulk/create_al_bulk_messages.sql
                     bulk/create_zeus_bulk_message_statuses.sql bulk/setup_master.sql bulk/create_zeus_short_links.sql
                     bulk/create_player_contact_phone_infos.sql
                     bulk/create_zeus_short_link_clicks.sql 0-scripts/z_grant_roles.sql]
      sql_source_dir = Rails.root.join('spec', 'fixtures', 'app_configs', 'bulk_msg_sql')
      SetupHelper.setup_app_db sql_source_dir, sql_files
    end
  end

  def self.validate_db_setup
    puts 'DB validation'

    # Ensure we are set up for this test
    pgpass = File.read("#{ENV['HOME']}/.pgpass")
    res = pgpass.include?(db_name) || pgpass.include?('localhost:5432:*')
    raise ".pgpass does not contain entry for database #{db_name}" unless res

    q = ActiveRecord::Base.connection.execute "select * from pg_catalog.pg_roles where rolname='fphsetl'"
    res = q.ntuples
    raise "Database #{db_name} does not have role fphsetl set up" unless res == 1
  end

  def self.migrate_if_needed
    puts 'Check migrations'

    # Outside the current transaction
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        dirname = 'db/migrations'
        mc = ActiveRecord::MigrationContext.new(dirname)
        if mc.needs_migration?
          puts 'Running migrations'
          mc.migrate
        end
      end
    end.join
  end

  def self.reload_configs
    Rails.logger.info 'Reload configs'
    AppControl.define_models
    DynamicModel.enable_active_configurations
    ItemFlag.enable_active_configurations
    ActivityLog.enable_active_configurations
    ExternalIdentifier.enable_active_configurations
    DynamicModel.routes_reload
  end

  def self.feature_setup(_options = {})
    Rails.logger.info 'Feature setup'
    Seeds.setup
    # MasterDataSupport.create_data_set_outside_tx options
  end

  def self.setup_al_player_contact_emails
    Rails.logger.info 'Setting up al player contact emails'
    return if ActivityLog.connection.table_exists? 'activity_log_player_contact_emails'

    TableGenerators.activity_logs_table('activity_log_player_contact_emails', 'player_contacts', true,
                                        'data', 'select_email_direction', 'select_who',
                                        'emailed_when', 'select_result', 'select_next_step', 'follow_up_when',
                                        'protocol_id', 'notes', 'set_related_player_contact_rank')
    Rails.cache.clear
  end

  # Setup Activity Log Player Contact Phones
  def self.setup_al_player_contact_phones
    Rails.logger.info 'Setting up al player contact phones'
    # Ensure that we seed the database, otherwise the PlayerContactPhonesController class does not exist

    Seeds::GeneralSelections.setup
    Seeds::ActivityLogPlayerContactPhone.setup

    reload_configs

    unless defined? ActivityLog::PlayerContactPhone
      raise 'Activity Log for Player Contact Phones has not been setup correctly.'
    end

    ActivityLog::PlayerContactPhone.definition.update_tracker_events
  end

  # Setup a general Activity Log, with the template of an Activity Log Player Contact Phones, but
  # named uniquely and attached to chosen item_type / rec_type
  def self.setup_al_gen_tests(name, process_name, item_type, rec_type: nil)
    Seeds::GeneralSelections.setup if item_type&.to_s == 'player_contact'

    itn = ActivityLog.item_type_name(item_type, process_name, rec_type)
    tname = 'activity_log_' + itn.pluralize
    cname = 'ActivityLog::' + itn.ns_camelize

    unless ActivityLog.connection.table_exists? tname
      TableGenerators.activity_logs_table(
        tname,
        item_type.to_s.pluralize,
        true,
        'data',
        'select_call_direction',
        'select_who',
        'called_when',
        'select_result',
        'select_next_step',
        'follow_up_when',
        'notes',
        'protocol_id',
        'set_related_player_contact_rank',
        'tag_select_allowed',
        'result_json',
        'created_by_user_id'
      )
    end

    res = ActivityLog.find_or_initialize_by(
      name: name, item_type: item_type,
      rec_type: rec_type,
      process_name: process_name,
      disabled: false,
      action_when_attribute: 'called_when',
      field_list: 'data, select_call_direction, select_who, called_when, select_result, select_next_step,'\
                  'follow_up_when, notes, protocol_id, set_related_player_contact_rank',
      blank_log_field_list: 'select_who, called_when, select_next_step, follow_up_when, notes, protocol_id'
    )
    ActivityLogSupport.cleanup_matching_activity_logs(item_type, rec_type, process_name, admin: auto_admin, excluding_id: res&.id)

    unless res.active_model_configuration?
      # If this was a new item, set an admin. Also set disabled nil, since this forces regeneration of the model
      res.update!(current_admin: auto_admin) unless res.admin

      app_type = Admin::AppType.active.first
      # Ensure there is at least one user access control, otherwise we won't re-enable the process on future loads
      res.other_regenerate_actions
      res.add_user_access_controls force: true, app_type: app_type
      res.update_tracker_events
      reload_configs
    end

    # Check implementation
    test = ActivityLog.active.where(name: name).count == 1

    raise "Failed setup of activity log #{name}" unless test

    res.implementation_class
    cname.constantize

    res
  end

  def self.setup_ext_identifier(name = 'test7', implementation_table_name: nil, implementation_attr_name: nil)
    Rails.logger.info "Setting up external identifier #{name}"
    @implementation_table_name = implementation_table_name || "test_external_#{name}_identifiers"
    @implementation_attr_name = implementation_attr_name || "test_#{name}_id"
    return if ActiveRecord::Base.connection.table_exists? @implementation_table_name

    TableGenerators.external_identifiers_table(@implementation_table_name, true, @implementation_attr_name)
  end

  def self.setup_test_app
    app_name = "bhs_model_#{rand(100_000_000)}"

    config_dir = Rails.root.join('spec', 'fixtures', 'app_configs', 'config_files')
    config_fn = 'bhs_app_type_test_config.json'
    SetupHelper.setup_app_from_import app_name, config_dir, config_fn

    new_app_type = Admin::AppType.where(name: app_name).active.first
    Admin::UserAccessControl.active.where(
      app_type_id: new_app_type.id,
      resource_type: %i[external_id_assignments limited_access]
    ).update_all(disabled: true)

    new_app_type
  end

  def self.setup_ref_data_app
    app_name = 'ref-data'

    config_dir = Rails.root.join('spec', 'fixtures', 'app_configs', 'config_files')
    config_fn = 'ref-data_config.yaml'
    SetupHelper.setup_app_from_import app_name, config_dir, config_fn

    a = Admin::AppType.where(name: app_name).active.first
    FileUtils.rm_rf "#{NfsStore::Manage::Filesystem.nfs_store_directory}/gid601/app-type-#{a.id}"
    FileUtils.mkdir_p "#{NfsStore::Manage::Filesystem.nfs_store_directory}/gid601/app-type-#{a.id}/containers"
    a
  end

  # Setup an app from an import configuration (json or yaml)
  #
  # @param [String] name the name of the app to be set
  # @param [String] sql_source_dir location of the SQL files to be run
  # @param [String] sql_files list of SQL files to be run through PSQL
  # @param [String] config_dir location of the configuration file
  # @param [String] config_fn filename of the configuration file (must have file extension .json or .yaml)
  # @return [Array(Admin::AppType, Hash)] returns the results from Admin::AppType.import_config
  #
  def self.setup_app_db(sql_source_dir, sql_files)
    sql_files.each do |fn|
      sqlfn = Rails.root.join(sql_source_dir, fn)
      puts "Running psql: #{sqlfn}"
      `PGOPTIONS=--search_path=ml_app psql -v ON_ERROR_STOP=ON -d #{db_name} < #{sqlfn}`
    rescue ActiveRecord::StatementInvalid => e
      puts "Exception due to PG error?... #{e}"
    end
  end

  def self.setup_app_from_import(name, config_dir, config_fn)
    admin = auto_admin

    als = ActivityLog.active.where(name: name)
    als.where('id <> ?', als.first&.id).update_all(disabled: true) if als.count != 1

    format = config_fn.split('.').last.to_sym

    res = Admin::AppType.import_config File.read(Rails.root.join(config_dir, config_fn)), admin, name: name,
                                                                                                 format: format

    reload_configs

    res
  end

  # Used only to get responses from live API requests so they can be
  # made into stub_request arguments
  def self.get_webmock_responses
    WebMock.allow_net_connect!
    WebMock.after_request do |request_signature, response|
      stubbing_instructions =
        WebMock::RequestSignatureSnippet
        .new(request_signature)
        .stubbing_instructions
      begin
        json = JSON.parse(response.body)
      rescue JSON::ParserError
        json = response.body
      end
      parsed_body = json
      puts '===== outgoing request ======================='
      puts stubbing_instructions
      puts
      puts 'parsed body:'
      puts
      pp parsed_body
      puts 'response headers'
      puts
      puts response.headers
      puts
      puts '=============================================='
      puts
    end
  end
end
