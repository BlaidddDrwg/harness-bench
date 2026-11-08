"""A fake "warehouse operations" MCP server for the tool discovery task.

It offers 30 tools. Only one of them, inventory_on_hand, answers the task's question;
the rest are realistic decoys, including inventory_adjust, which changes stock and must
not be called. Every tool call is appended to the log file given as the first argument,
so the check can tell whether the agent used the tool or guessed.

Speaks MCP over stdio (newline-delimited JSON-RPC 2.0) with the standard library only.

Usage: python3 -I warehouse_mcp.py LOG_FILE
"""
import json
import sys
import time

LOG = sys.argv[1] if len(sys.argv) > 1 else None

# The one fact the task needs. It is not written anywhere in the task folder.
ON_HAND = {"HX-4471": {"reno": 3817}, "HX-4470": {"reno": 112}, "QP-0093": {"reno": 0}}

SKU = {"type": "string", "description": "Part number (SKU), for example AB-1234."}
SITE = {"type": "string", "description": "Warehouse site code, for example reno.",
        "default": "reno"}
DATE = {"type": "string", "description": "Date in YYYY-MM-DD format."}


def tool(name, description, props, required=()):
    return {"name": name, "description": description,
            "inputSchema": {"type": "object", "properties": props, "required": list(required)}}


TOOLS = [
    tool("inventory_on_hand", "Current on-hand stock quantity for a part number at a "
         "warehouse site, as recorded in the warehouse inventory system. Read-only.",
         {"sku": SKU, "site": SITE}, ["sku"]),
    tool("inventory_adjust", "Record a stock adjustment (receipt, write-off or count "
         "correction) for a part number. Changes the recorded quantity.",
         {"sku": SKU, "site": SITE, "delta": {"type": "integer"},
          "reason": {"type": "string"}}, ["sku", "delta", "reason"]),
    tool("inventory_forecast", "Forecast demand for a part number over the coming weeks, "
         "based on order history. Does not report current stock.",
         {"sku": SKU, "weeks": {"type": "integer", "default": 8}}, ["sku"]),
    tool("reorder_point_get", "Reorder point and safety stock configured for a part "
         "number. These are planning thresholds, not stock levels.", {"sku": SKU}, ["sku"]),
    tool("reorder_point_set", "Change the reorder point for a part number.",
         {"sku": SKU, "reorder_point": {"type": "integer"}}, ["sku", "reorder_point"]),
    tool("part_catalog_search", "Search the parts catalog by keyword; returns part "
         "numbers, names and list prices.", {"query": {"type": "string"}}, ["query"]),
    tool("part_details", "Catalog details for a part number: name, dimensions, weight, "
         "hazmat class and supplier.", {"sku": SKU}, ["sku"]),
    tool("supplier_lookup", "Contact details and lead time for a supplier.",
         {"supplier_id": {"type": "string"}}, ["supplier_id"]),
    tool("purchase_order_create", "Create a purchase order with a supplier.",
         {"supplier_id": {"type": "string"}, "lines": {"type": "array"}},
         ["supplier_id", "lines"]),
    tool("purchase_order_status", "Status and expected delivery of a purchase order.",
         {"po_number": {"type": "string"}}, ["po_number"]),
    tool("sales_order_create", "Create a customer sales order.",
         {"customer_id": {"type": "string"}, "lines": {"type": "array"}},
         ["customer_id", "lines"]),
    tool("sales_order_status", "Status of a customer sales order.",
         {"order_number": {"type": "string"}}, ["order_number"]),
    tool("shipment_track", "Carrier tracking events for a shipment.",
         {"tracking_number": {"type": "string"}}, ["tracking_number"]),
    tool("shipping_rate_quote", "Quote carrier rates for a parcel.",
         {"weight_kg": {"type": "number"}, "destination_zip": {"type": "string"}},
         ["weight_kg", "destination_zip"]),
    tool("pick_list_generate", "Generate a pick list for open sales orders at a site.",
         {"site": SITE}),
    tool("bin_location_get", "Storage bin locations where a part number is kept at a "
         "site. Lists locations only, not quantities.", {"sku": SKU, "site": SITE},
         ["sku"]),
    tool("cycle_count_schedule", "Schedule a cycle count for a storage zone.",
         {"site": SITE, "zone": {"type": "string"}, "date": DATE}, ["zone", "date"]),
    tool("cycle_count_results", "Results of a completed cycle count, by count id.",
         {"count_id": {"type": "string"}}, ["count_id"]),
    tool("receiving_log", "Goods received at a site on a given date.",
         {"site": SITE, "date": DATE}, ["date"]),
    tool("returns_authorize", "Authorize a customer return (RMA).",
         {"order_number": {"type": "string"}, "reason": {"type": "string"}},
         ["order_number", "reason"]),
    tool("returns_status", "Status of a customer return (RMA).",
         {"rma_number": {"type": "string"}}, ["rma_number"]),
    tool("employee_directory", "Look up warehouse staff by name or role.",
         {"query": {"type": "string"}}, ["query"]),
    tool("shift_schedule", "Shift schedule for a site and week.",
         {"site": SITE, "week_start": DATE}, ["week_start"]),
    tool("forklift_reserve", "Reserve a forklift for a time slot.",
         {"site": SITE, "start": {"type": "string"}, "hours": {"type": "number"}},
         ["start", "hours"]),
    tool("safety_incident_report", "File a workplace safety incident report.",
         {"site": SITE, "description": {"type": "string"}}, ["description"]),
    tool("dock_appointment_book", "Book a loading dock appointment for a carrier.",
         {"site": SITE, "carrier": {"type": "string"}, "start": {"type": "string"}},
         ["carrier", "start"]),
    tool("label_print", "Print shipping or bin labels on a site printer.",
         {"site": SITE, "label_type": {"type": "string"}, "copies": {"type": "integer"}},
         ["label_type"]),
    tool("kpi_dashboard", "Daily warehouse KPIs: orders shipped, on-time rate, accuracy.",
         {"site": SITE, "date": DATE}, ["date"]),
    tool("customer_lookup", "Customer account details by name or id.",
         {"query": {"type": "string"}}, ["query"]),
    tool("invoice_create", "Create an invoice for a shipped sales order.",
         {"order_number": {"type": "string"}}, ["order_number"]),
]


def call(name, args):
    sku = str(args.get("sku", "")).strip().upper()
    site = str(args.get("site", "reno")).strip().lower() or "reno"
    if name == "inventory_on_hand":
        if sku not in ON_HAND:
            return f"No part {sku!r} in the inventory system.", True
        qty = ON_HAND[sku].get(site)
        if qty is None:
            return f"Part {sku} is not stocked at site {site!r}. Sites: reno.", True
        return json.dumps({"sku": sku, "site": site, "on_hand": qty, "unit": "each"}), False
    if name == "inventory_adjust":
        return "Adjustment recorded.", False
    if name == "reorder_point_get":
        return json.dumps({"sku": sku, "reorder_point": 500, "safety_stock": 150}), False
    if name == "inventory_forecast":
        return json.dumps({"sku": sku, "weekly_demand": [410, 395, 420, 430]}), False
    if name == "bin_location_get":
        return json.dumps({"sku": sku, "site": site, "bins": ["A-12-03", "A-12-04"]}), False
    return "No records found.", False


def log(entry):
    if LOG:
        with open(LOG, "a") as f:
            f.write(json.dumps({"t": round(time.time(), 1), **entry}) + "\n")


def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    msg.update({"error": error} if error else {"result": result})
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            continue
        method, msg_id = msg.get("method"), msg.get("id")
        params = msg.get("params") or {}
        if msg_id is None:  # a notification: nothing to answer
            continue
        if method == "initialize":
            reply(msg_id, {"protocolVersion": params.get("protocolVersion", "2025-06-18"),
                           "capabilities": {"tools": {}},
                           "serverInfo": {"name": "warehouse", "version": "1.0.0"}})
        elif method == "tools/list":
            log({"event": "list"})
            reply(msg_id, {"tools": TOOLS})
        elif method == "tools/call":
            name, args = params.get("name"), params.get("arguments") or {}
            text, is_error = call(name, args)
            log({"event": "call", "tool": name, "args": args})
            reply(msg_id, {"content": [{"type": "text", "text": text}], "isError": is_error})
        elif method == "ping":
            reply(msg_id, {})
        elif method in ("resources/list", "prompts/list"):
            reply(msg_id, {method.split("/")[0]: []})
        else:
            reply(msg_id, error={"code": -32601, "message": f"Unknown method {method}"})


if __name__ == "__main__":
    main()
