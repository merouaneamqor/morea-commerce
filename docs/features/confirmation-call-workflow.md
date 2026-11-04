# Manager and confirmation-agent call workflow

Managers create an ordinary order under Orders and create a staff account under Team. Choose Confirmation agent for a non-admin worker; supervisors need explicit Admin access. An invalid supervisor/access combination is rejected instead of creating an account that cannot sign in.

The agent signs in, opens the confirmation queue and clocks in before handling orders. Start call claims the order and starts a server-side timer, then opens My claims. Choose the result and use Finish call and save to record the result and measured duration. Close call without a result stops the timer without confirming the order. These controls record work; they do not dial a telephone automatically.

Confirmation changes the order state and reserves local stock through the existing transition service. It records the responsible agent, result and call duration together. It does not dispatch a parcel. Own statistics and the manager's confirmation performance report read the stored attempt. Revenue and pay metrics may use delivery rather than confirmation and need not increase at this point.

JSON clients must request `Accept: application/json`; queue HTML forms redirect back to My claims with a notice or error. Partial contact edits preserve omitted fields and product lines. Explicitly empty lines remain invalid.

## Verification

Use an isolated `RAILS_ENV=test` database and disconnected providers:

```sh
bundle exec rspec spec/requests/confirmation_workflow_spec.rb spec/requests/call_panel_spec.rb spec/requests/orders_flow_spec.rb
bundle exec rspec spec/models/confirmation_agent_spec.rb spec/requests/confirmation_dashboard_spec.rb spec/services/confirmations
```

The workflow regression creates the order and agent through HTTP forms, signs in separately as manager and agent, simulates a timed call, and verifies confirmation, stock, own statistics and manager visibility. It also covers invalid staff access and partial contact edits. Test data is synthetic and no telephone, messaging or courier service is called.
