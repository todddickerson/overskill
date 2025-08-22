# Test Suite Audit Report
*Generated: August 22, 2025 at 03:51 PM*

## 📊 Executive Summary

- **Total Test Files**: 129
- **Golden Flow Coverage**: 79 tests (61.2%)
- **Recommended to Skip**: 7 tests

## 🛡️ Golden Flow Coverage Analysis

### App Generation Flow
**Description**: Prompt → Generate → Preview → Deploy
**Coverage Level**: Comprehensive (55 tests)

**Covering Tests**:
- test/system/app_generation_test.rb
- test/system/authentication_test.rb
- test/system/super_scaffolding/insight/insight_test.rb
- test/system/super_scaffolding/personality_disposition/personality_disposition_test.rb
- test/system/super_scaffolding/personality_observation/personality_observation_test.rb
- test/system/super_scaffolding/project/project_test.rb
- test/system/super_scaffolding/projects_step/projects_step_test.rb
- test/system/super_scaffolding/test_site/test_site_test.rb
- test/system/super_scaffolding/webhook/webhook_test.rb
- test/integration/app_generation_flow_test.rb
- test/controllers/account/app_editors_controller_test.rb
- test/controllers/api/v1/app_audit_logs_controller_test.rb
- test/controllers/api/v1/app_collaborators_controller_test.rb
- test/controllers/api/v1/app_env_vars_controller_test.rb
- test/controllers/api/v1/app_files_controller_test.rb
- test/controllers/api/v1/app_generations_controller_test.rb
- test/controllers/api/v1/app_security_policies_controller_test.rb
- test/controllers/api/v1/app_settings_controller_test.rb
- test/controllers/api/v1/app_versions_controller_test.rb
- test/controllers/api/v1/apps_controller_test.rb
- test/controllers/api/v1/creator_profiles_controller_test.rb
- test/controllers/api/v1/follows_controller_test.rb
- test/controllers/api/v1/platform/access_tokens_controller_test.rb
- test/controllers/api/v1/scaffolding/completely_concrete/tangible_things_controller_test.rb
- test/models/app_chat_message_test.rb
- test/models/app_deployment_test.rb
- test/models/app_generation_test.rb
- test/models/app_github_migration_test.rb
- test/models/app_test.rb
- test/services/ai/ai_tool_service_test.rb
- test/services/ai/app_builder_v5_line_replace_test.rb
- test/services/ai/app_builder_v5_test.rb
- test/services/ai/app_builder_v5_tools_test.rb
- test/services/ai/app_generator_service_test.rb
- test/services/ai/app_version_incremental_test.rb
- test/services/ai/chat_message_processor_test.rb
- test/services/ai/file_context_analyzer_test.rb
- test/services/ai/image_generation_service_test.rb
- test/services/ai/open_router_client_test.rb
- test/services/ai/prompts/agent_prompt_service_test.rb
- test/services/ai/prompts/cached_prompt_builder_test.rb
- test/services/ai/routing_generator_service_test.rb
- test/services/ai/shared_template_service_test.rb
- test/services/deployment/cloudflare_api_client_test.rb
- test/services/deployment/cloudflare_worker_optimizer_test.rb
- test/services/deployment/cloudflare_worker_service_test.rb
- test/services/deployment/cloudflare_workers_build_service_test.rb
- test/services/deployment/cloudflare_workers_deployer_test.rb
- test/services/deployment/github_repository_service_test.rb
- test/services/deployment/vite_builder_service_test.rb
- test/services/perplexity_content_service_test.rb
- test/services/unified_ai_coordinator_test.rb
- test/jobs/app_generation_job_test.rb
- test/jobs/deploy_app_job_test.rb
- test/jobs/process_app_update_job_test.rb

### User Authentication Flow
**Description**: Registration → Login → Team Management
**Coverage Level**: Good (21 tests)

**Covering Tests**:
- test/system/account_management_test.rb
- test/system/account_test.rb
- test/system/application_platform_test.rb
- test/system/authentication_test.rb
- test/system/dates_helper_test.rb
- test/system/fields_test.rb
- test/system/invitations_test.rb
- test/system/membership_test.rb
- test/system/reactivity_system_test.rb
- test/system/tangible_thing_test.rb
- test/system/teams_test.rb
- test/system/two_factor_authentication_test.rb
- test/controllers/account/app_editors_controller_test.rb
- test/controllers/account/scaffolding/absolutely_abstract/creative_concepts_controller_test.rb
- test/controllers/account/scaffolding/completely_concrete/tangible_things_controller_test.rb
- test/controllers/account/teams_controller_test.rb
- test/controllers/api/v1/platform/applications_controller_test.rb
- test/controllers/application/localization_test.rb
- test/services/ai/ai_tool_service_test.rb
- test/services/ai/chat_message_processor_test.rb
- test/services/ai/file_context_analyzer_test.rb

### App Publishing Flow
**Description**: Preview → Production → Subdomain Management
**Coverage Level**: Comprehensive (25 tests)

**Covering Tests**:
- test/system/action_models_test.rb
- test/system/app_generation_test.rb
- test/integration/app_generation_flow_test.rb
- test/controllers/account/app_editors_controller_test.rb
- test/controllers/api/v1/app_versions_controller_test.rb
- test/controllers/api/v1/apps_controller_test.rb
- test/models/app_deployment_test.rb
- test/models/app_github_migration_test.rb
- test/models/app_test.rb
- test/models/deployment_log_test.rb
- test/services/ai/ai_tool_service_test.rb
- test/services/ai/app_version_incremental_test.rb
- test/services/ai/chat_message_processor_test.rb
- test/services/ai/file_context_analyzer_test.rb
- test/services/ai/image_generation_service_test.rb
- test/services/deployment/cloudflare_api_client_test.rb
- test/services/deployment/cloudflare_worker_optimizer_test.rb
- test/services/deployment/cloudflare_worker_service_test.rb
- test/services/deployment/cloudflare_workers_build_service_test.rb
- test/services/deployment/cloudflare_workers_deployer_test.rb
- test/services/deployment/github_repository_service_test.rb
- test/services/deployment/vite_builder_service_test.rb
- test/services/unified_ai_coordinator_test.rb
- test/jobs/deploy_app_job_test.rb
- test/jobs/process_app_update_job_test.rb

### Realtime Chat Flow
**Description**: Message → AI Response → Tool Execution → UI Update
**Coverage Level**: Comprehensive (12 tests)

**Covering Tests**:
- test/system/app_generation_test.rb
- test/integration/app_generation_flow_test.rb
- test/controllers/account/app_editors_controller_test.rb
- test/models/app_chat_message_test.rb
- test/models/app_test.rb
- test/services/ai/app_builder_v5_line_replace_test.rb
- test/services/ai/app_builder_v5_test.rb
- test/services/ai/app_builder_v5_tools_test.rb
- test/services/ai/app_version_incremental_test.rb
- test/services/ai/chat_message_processor_test.rb
- test/services/unified_ai_coordinator_test.rb
- test/jobs/process_app_update_job_test.rb

**Coverage Gaps**:
- ActionCable WebSocket testing

### File Management Flow
**Description**: Create → Edit → Validate → Save
**Coverage Level**: Comprehensive (26 tests)

**Covering Tests**:
- test/system/app_generation_test.rb
- test/integration/app_generation_flow_test.rb
- test/controllers/account/app_editors_controller_test.rb
- test/controllers/api/v1/app_files_controller_test.rb
- test/controllers/api/v1/app_versions_controller_test.rb
- test/models/app_file_test.rb
- test/models/app_github_migration_test.rb
- test/models/app_test.rb
- test/models/app_version_file_test.rb
- test/models/app_version_test.rb
- test/services/ai/ai_tool_service_test.rb
- test/services/ai/app_builder_v5_line_replace_test.rb
- test/services/ai/app_builder_v5_tools_test.rb
- test/services/ai/app_generator_service_test.rb
- test/services/ai/app_version_incremental_test.rb
- test/services/ai/base_context_service_test.rb
- test/services/ai/chat_message_processor_test.rb
- test/services/ai/code_validator_service_test.rb
- test/services/ai/code_validator_test.rb
- test/services/ai/file_context_analyzer_test.rb
- test/services/ai/shared_template_service_test.rb
- test/services/deployment/cloudflare_worker_service_test.rb
- test/services/deployment/vite_builder_service_test.rb
- test/services/unified_ai_coordinator_test.rb
- test/jobs/deploy_app_job_test.rb
- test/jobs/process_app_update_job_test.rb

## 🏷️ Test Classification Results

### High Priority Tests (79)

**account_management_test** (`test/system/account_management_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**account_test** (`test/system/account_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**action_models_test** (`test/system/action_models_test.rb`)
- Golden Flows: app_publishing_flow
- Recommendation: Keep and enhance

**app_generation_test** (`test/system/app_generation_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**application_platform_test** (`test/system/application_platform_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**authentication_test** (`test/system/authentication_test.rb`)
- Golden Flows: app_generation_flow, user_authentication_flow
- Recommendation: Keep and enhance

**dates_helper_test** (`test/system/dates_helper_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**fields_test** (`test/system/fields_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**invitations_test** (`test/system/invitations_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**membership_test** (`test/system/membership_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**reactivity_system_test** (`test/system/reactivity_system_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**insight_test** (`test/system/super_scaffolding/insight/insight_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**personality_disposition_test** (`test/system/super_scaffolding/personality_disposition/personality_disposition_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**personality_observation_test** (`test/system/super_scaffolding/personality_observation/personality_observation_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**project_test** (`test/system/super_scaffolding/project/project_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**projects_step_test** (`test/system/super_scaffolding/projects_step/projects_step_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**test_site_test** (`test/system/super_scaffolding/test_site/test_site_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**webhook_test** (`test/system/super_scaffolding/webhook/webhook_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**tangible_thing_test** (`test/system/tangible_thing_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**teams_test** (`test/system/teams_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**two_factor_authentication_test** (`test/system/two_factor_authentication_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**app_generation_flow_test** (`test/integration/app_generation_flow_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**app_editors_controller_test** (`test/controllers/account/app_editors_controller_test.rb`)
- Golden Flows: app_generation_flow, user_authentication_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**creative_concepts_controller_test** (`test/controllers/account/scaffolding/absolutely_abstract/creative_concepts_controller_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**tangible_things_controller_test** (`test/controllers/account/scaffolding/completely_concrete/tangible_things_controller_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**teams_controller_test** (`test/controllers/account/teams_controller_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**app_audit_logs_controller_test** (`test/controllers/api/v1/app_audit_logs_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_collaborators_controller_test** (`test/controllers/api/v1/app_collaborators_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_env_vars_controller_test** (`test/controllers/api/v1/app_env_vars_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_files_controller_test** (`test/controllers/api/v1/app_files_controller_test.rb`)
- Golden Flows: app_generation_flow, file_management_flow
- Recommendation: Keep and enhance

**app_generations_controller_test** (`test/controllers/api/v1/app_generations_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_security_policies_controller_test** (`test/controllers/api/v1/app_security_policies_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_settings_controller_test** (`test/controllers/api/v1/app_settings_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_versions_controller_test** (`test/controllers/api/v1/app_versions_controller_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**apps_controller_test** (`test/controllers/api/v1/apps_controller_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**creator_profiles_controller_test** (`test/controllers/api/v1/creator_profiles_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**follows_controller_test** (`test/controllers/api/v1/follows_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**access_tokens_controller_test** (`test/controllers/api/v1/platform/access_tokens_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**applications_controller_test** (`test/controllers/api/v1/platform/applications_controller_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**tangible_things_controller_test** (`test/controllers/api/v1/scaffolding/completely_concrete/tangible_things_controller_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**localization_test** (`test/controllers/application/localization_test.rb`)
- Golden Flows: user_authentication_flow
- Recommendation: Keep and enhance

**app_chat_message_test** (`test/models/app_chat_message_test.rb`)
- Golden Flows: app_generation_flow, realtime_chat_flow
- Recommendation: Keep and enhance

**app_deployment_test** (`test/models/app_deployment_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**app_file_test** (`test/models/app_file_test.rb`)
- Golden Flows: file_management_flow
- Recommendation: Keep and enhance

**app_generation_test** (`test/models/app_generation_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**app_github_migration_test** (`test/models/app_github_migration_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**app_test** (`test/models/app_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**app_version_file_test** (`test/models/app_version_file_test.rb`)
- Golden Flows: file_management_flow
- Recommendation: Keep and enhance

**app_version_test** (`test/models/app_version_test.rb`)
- Golden Flows: file_management_flow
- Recommendation: Keep and enhance

**deployment_log_test** (`test/models/deployment_log_test.rb`)
- Golden Flows: app_publishing_flow
- Recommendation: Keep and enhance

**ai_tool_service_test** (`test/services/ai/ai_tool_service_test.rb`)
- Golden Flows: app_generation_flow, user_authentication_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**app_builder_v5_line_replace_test** (`test/services/ai/app_builder_v5_line_replace_test.rb`)
- Golden Flows: app_generation_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**app_builder_v5_test** (`test/services/ai/app_builder_v5_test.rb`)
- Golden Flows: app_generation_flow, realtime_chat_flow
- Recommendation: Keep and enhance

**app_builder_v5_tools_test** (`test/services/ai/app_builder_v5_tools_test.rb`)
- Golden Flows: app_generation_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**app_generator_service_test** (`test/services/ai/app_generator_service_test.rb`)
- Golden Flows: app_generation_flow, file_management_flow
- Recommendation: Keep and enhance

**app_version_incremental_test** (`test/services/ai/app_version_incremental_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**base_context_service_test** (`test/services/ai/base_context_service_test.rb`)
- Golden Flows: file_management_flow
- Recommendation: Keep and enhance

**chat_message_processor_test** (`test/services/ai/chat_message_processor_test.rb`)
- Golden Flows: app_generation_flow, user_authentication_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**code_validator_service_test** (`test/services/ai/code_validator_service_test.rb`)
- Golden Flows: file_management_flow
- Recommendation: Keep and enhance

**code_validator_test** (`test/services/ai/code_validator_test.rb`)
- Golden Flows: file_management_flow
- Recommendation: Keep and enhance

**file_context_analyzer_test** (`test/services/ai/file_context_analyzer_test.rb`)
- Golden Flows: app_generation_flow, user_authentication_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**image_generation_service_test** (`test/services/ai/image_generation_service_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**open_router_client_test** (`test/services/ai/open_router_client_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**agent_prompt_service_test** (`test/services/ai/prompts/agent_prompt_service_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**cached_prompt_builder_test** (`test/services/ai/prompts/cached_prompt_builder_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**routing_generator_service_test** (`test/services/ai/routing_generator_service_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**shared_template_service_test** (`test/services/ai/shared_template_service_test.rb`)
- Golden Flows: app_generation_flow, file_management_flow
- Recommendation: Keep and enhance

**cloudflare_api_client_test** (`test/services/deployment/cloudflare_api_client_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**cloudflare_worker_optimizer_test** (`test/services/deployment/cloudflare_worker_optimizer_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**cloudflare_worker_service_test** (`test/services/deployment/cloudflare_worker_service_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**cloudflare_workers_build_service_test** (`test/services/deployment/cloudflare_workers_build_service_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**cloudflare_workers_deployer_test** (`test/services/deployment/cloudflare_workers_deployer_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**github_repository_service_test** (`test/services/deployment/github_repository_service_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow
- Recommendation: Keep and enhance

**vite_builder_service_test** (`test/services/deployment/vite_builder_service_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**perplexity_content_service_test** (`test/services/perplexity_content_service_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**unified_ai_coordinator_test** (`test/services/unified_ai_coordinator_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

**app_generation_job_test** (`test/jobs/app_generation_job_test.rb`)
- Golden Flows: app_generation_flow
- Recommendation: Keep and enhance

**deploy_app_job_test** (`test/jobs/deploy_app_job_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, file_management_flow
- Recommendation: Keep and enhance

**process_app_update_job_test** (`test/jobs/process_app_update_job_test.rb`)
- Golden Flows: app_generation_flow, app_publishing_flow, realtime_chat_flow, file_management_flow
- Recommendation: Keep and enhance

### Medium Priority Tests (43)

**animations_test** (`test/system/animations_test.rb`)
- Recommendation: Review manually

**basics_test** (`test/system/basics_test.rb`)
- Recommendation: Review manually

**super_scaffolding_test** (`test/system/bullet_train_gems/audit_logs/super_scaffolding_test.rb`)
- Recommendation: Review manually

**invitation_details_test** (`test/system/invitation_details_test.rb`)
- Recommendation: Review manually

**invitation_lists_test** (`test/system/invitation_lists_test.rb`)
- Recommendation: Review manually

**pagination_test** (`test/system/pagination_test.rb`)
- Recommendation: Review manually

**resolver_system_test** (`test/system/resolver_system_test.rb`)
- Recommendation: Review manually

**open_api_test** (`test/system/super_scaffolding/open_api_test.rb`)
- Recommendation: Review manually

**partial_test_test** (`test/system/super_scaffolding/partial_test/partial_test_test.rb`)
- Recommendation: Review manually

**test_file_test** (`test/system/super_scaffolding/test_file/test_file_test.rb`)
- Recommendation: Review manually

**open_api_controller_test** (`test/controllers/api/open_api_controller_test.rb`)
- Recommendation: Review manually

**teams_controller_test** (`test/controllers/api/v1/teams_controller_test.rb`)
- Recommendation: Review manually

**users_controller_test** (`test/controllers/api/v1/users_controller_test.rb`)
- Recommendation: Review manually

**ability_test** (`test/models/ability_test.rb`)
- Recommendation: Review manually

**app_api_call_test** (`test/models/app_api_call_test.rb`)
- Recommendation: Review manually

**app_api_integration_test** (`test/models/app_api_integration_test.rb`)
- Recommendation: Review manually

**app_audit_log_test** (`test/models/app_audit_log_test.rb`)
- Recommendation: Review manually

**app_auth_setting_test** (`test/models/app_auth_setting_test.rb`)
- Recommendation: Review manually

**app_collaborator_test** (`test/models/app_collaborator_test.rb`)
- Recommendation: Review manually

**app_domain_test** (`test/models/app_domain_test.rb`)
- Recommendation: Review manually

**app_env_var_test** (`test/models/app_env_var_test.rb`)
- Recommendation: Review manually

**app_o_auth_provider_test** (`test/models/app_o_auth_provider_test.rb`)
- Recommendation: Review manually

**app_security_policy_test** (`test/models/app_security_policy_test.rb`)
- Recommendation: Review manually

**app_setting_test** (`test/models/app_setting_test.rb`)
- Recommendation: Review manually

**app_table_column_test** (`test/models/app_table_column_test.rb`)
- Recommendation: Review manually

**app_table_test** (`test/models/app_table_test.rb`)
- Recommendation: Review manually

**base_test** (`test/models/base_test.rb`)
- Recommendation: Review manually

**build_log_test** (`test/models/build_log_test.rb`)
- Recommendation: Review manually

**creator_profile_test** (`test/models/creator_profile_test.rb`)
- Recommendation: Review manually

**feature_flag_test** (`test/models/feature_flag_test.rb`)
- Recommendation: Review manually

**follow_test** (`test/models/follow_test.rb`)
- Recommendation: Review manually

**github_installation_test** (`test/models/integrations/github_installation_test.rb`)
- Recommendation: Review manually

**google_oauth2_installation_test** (`test/models/integrations/google_oauth2_installation_test.rb`)
- Recommendation: Review manually

**stripe_installation_test** (`test/models/integrations/stripe_installation_test.rb`)
- Recommendation: Review manually

**invitation_test** (`test/models/invitation_test.rb`)
- Recommendation: Review manually

**github_account_test** (`test/models/oauth/github_account_test.rb`)
- Recommendation: Review manually

**google_oauth2_account_test** (`test/models/oauth/google_oauth2_account_test.rb`)
- Recommendation: Review manually

**stripe_account_test** (`test/models/oauth/stripe_account_test.rb`)
- Recommendation: Review manually

**user_test** (`test/models/user_test.rb`)
- Recommendation: Review manually

**line_offset_tracker_test** (`test/services/ai/line_offset_tracker_test.rb`)
- Recommendation: Review manually

**thinking_blocks_format_test** (`test/services/ai/thinking_blocks_format_test.rb`)
- Recommendation: Review manually

**supabase_service_test** (`test/services/supabase_service_test.rb`)
- Recommendation: Review manually

**web_content_extraction_service_test** (`test/services/web_content_extraction_service_test.rb`)
- Recommendation: Review manually

### Low Priority Tests (7)

**webhooks_system_test** (`test/system/webhooks_system_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Webhook test - not part of core user workflows

**creative_concept_test** (`test/models/scaffolding/absolutely_abstract/creative_concept_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Scaffolding test - not relevant to current OverSkill golden flows

**tangible_thing_test** (`test/models/scaffolding/completely_concrete/tangible_thing_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Scaffolding test - not relevant to current OverSkill golden flows

**github_account_webhook_test** (`test/models/webhooks/incoming/oauth/github_account_webhook_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Webhook test - not part of core user workflows

**google_oauth2_account_webhook_test** (`test/models/webhooks/incoming/oauth/google_oauth2_account_webhook_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Webhook test - not part of core user workflows

**stripe_installation_webhook_test** (`test/models/webhooks/incoming/stripe_installation_webhook_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Webhook test - not part of core user workflows

**stripe_webhook_test** (`test/models/webhooks/incoming/stripe_webhook_test.rb`)
- Recommendation: Skip with reason
- Skip Reason: Webhook test - not part of core user workflows

## 🎯 Recommended Actions

### Tests to Comment Out/Skip

```ruby
# Add to test files or create test helper method:

# test/system/webhooks_system_test.rb
# Reason: Webhook test - not part of core user workflows
skip "webhooks_system_test - Webhook test - not part of core user workflows"

# test/models/scaffolding/absolutely_abstract/creative_concept_test.rb
# Reason: Scaffolding test - not relevant to current OverSkill golden flows
skip "creative_concept_test - Scaffolding test - not relevant to current OverSkill golden flows"

# test/models/scaffolding/completely_concrete/tangible_thing_test.rb
# Reason: Scaffolding test - not relevant to current OverSkill golden flows
skip "tangible_thing_test - Scaffolding test - not relevant to current OverSkill golden flows"

# test/models/webhooks/incoming/oauth/github_account_webhook_test.rb
# Reason: Webhook test - not part of core user workflows
skip "github_account_webhook_test - Webhook test - not part of core user workflows"

# test/models/webhooks/incoming/oauth/google_oauth2_account_webhook_test.rb
# Reason: Webhook test - not part of core user workflows
skip "google_oauth2_account_webhook_test - Webhook test - not part of core user workflows"

# test/models/webhooks/incoming/stripe_installation_webhook_test.rb
# Reason: Webhook test - not part of core user workflows
skip "stripe_installation_webhook_test - Webhook test - not part of core user workflows"

# test/models/webhooks/incoming/stripe_webhook_test.rb
# Reason: Webhook test - not part of core user workflows
skip "stripe_webhook_test - Webhook test - not part of core user workflows"
```
