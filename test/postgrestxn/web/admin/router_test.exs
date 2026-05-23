defmodule PostgRESTxn.Web.Admin.RouterTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  import Plug.Test

  alias PostgRESTxn.Web.Admin.Router

  setup_all do
    start_supervised!(PostgRESTxn.Repo)
    start_supervised!(PostgRESTxn.Metrics)
    :ok
  end

  describe "GET /metrics" do
    test "returns 200 with Prometheus text format" do
      conn = call_admin(:get, "/metrics")

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "content-type") |> List.first() =~ "text/plain"
    end

    test "response body includes our metric series after relevant events fire" do
      # Manually emit a stop event so the counter has something to report.
      :telemetry.execute(
        [:postgrestxn, :txn, :stop],
        %{duration: System.convert_time_unit(42, :millisecond, :native)},
        %{role: "web_anon", outcome: :ok}
      )

      :telemetry.execute(
        [:postgrestxn, :op, :stop],
        %{duration: System.convert_time_unit(7, :millisecond, :native)},
        %{op: "select", outcome: :ok}
      )

      body = call_admin(:get, "/metrics").resp_body

      # NOTE: telemetry_metrics_prometheus_core doesn't auto-append `_total`.
      assert body =~ ~r/postgrestxn_txn_count\{[^}]+\} [1-9]/
      assert body =~ ~r/postgrestxn_op_count\{[^}]+\} [1-9]/
      assert body =~ ~s|role="web_anon"|
      assert body =~ ~s|op="select"|
      assert body =~ ~s|outcome="ok"|

      # Histogram metrics:
      assert body =~ "postgrestxn_txn_duration_milliseconds_bucket"
      assert body =~ "postgrestxn_op_duration_milliseconds_bucket"
    end
  end

  describe "GET /live" do
    test "returns 200 unconditionally" do
      assert call_admin(:get, "/live").status == 200
    end
  end

  describe "GET /ready" do
    test "returns 200 when the DB pool is reachable" do
      assert call_admin(:get, "/ready").status == 200
    end
  end

  describe "GET /config" do
    test "returns the runtime config as JSON, with safe keys included" do
      conn = call_admin(:get, "/config")

      assert conn.status == 200
      body = JSON.decode!(conn.resp_body)

      assert body["env"] == "test"
      assert body["http_port"] == 4001
      assert body["admin_http_port"] == 9569
      assert body["db_schemas"] == ["public"]
      assert body["anon_role"] == nil
    end

    test "redacts secret-bearing keys when set, returns nil when unset" do
      # database_url is set in test.exs, jwt_secret is nil there.
      conn = call_admin(:get, "/config")
      body = JSON.decode!(conn.resp_body)

      # Password must be masked:
      assert body["database_url"] =~
               ~r{^postgres://postgres:\[REDACTED\]@localhost:5432/postgrestxn}

      assert body["jwt_secret"] == nil

      # Verify the raw URL is not present in the body.
      raw_db_url = Application.fetch_env!(:postgrestxn, :database_url)
      refute conn.resp_body =~ raw_db_url
    end
  end

  describe "catch-all" do
    test "unknown path returns 404" do
      conn = call_admin(:get, "/anything-else")
      assert conn.status == 404
    end
  end

  # Router driver:
  defp call_admin(method, path) do
    conn(method, path) |> Router.call(Router.init([]))
  end
end
