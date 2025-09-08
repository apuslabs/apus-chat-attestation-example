local json = require("json")

-- Backend AO Process Logic (Core Flow from section 2.5)

CurrentReference = CurrentReference or 0 -- Initialize or use existing reference counter
Tasks = Tasks or {}                      -- Your process's state where results are stored
Balances = Balances or "0"               -- Store balance information for each reference

APUS_ROUTER = "TED2PpCVx0KbkQtzEYBo0TRAO-HPJlpCMmUzch9ZL2g"

-- Handler to listen for prompts from your frontend
Handlers.add(
    "SendInfer",
    Handlers.utils.hasMatchingTag("Action", "Infer"),
    function(msg)
        local reference = msg["X-Reference"] or msg.Reference
        local requestReference = reference
        local request = {
            Target = APUS_ROUTER,
            Action = "Infer",
            ["X-Prompt"] = msg.Data,
            ["X-Reference"] = reference
        }
        if msg["X-Session"] then
            request["X-Session"] = msg["X-Session"]
        end
        if msg["X-Options"] then
            request["X-Options"] = msg["X-Options"]
        end
        Tasks[requestReference] = {
            prompt = request["X-Prompt"],
            options = request["X-Options"],
            session = request["X-Session"],
            reference = reference,
            status = "processing",
            starttime = os.time(),
        }
        Send({
            device = 'patch@1.0',
            cache = {
                tasks = Tasks
            }
        })
        ao.send(request)
    end
)

Handlers.add(
    "AcceptResponse",
    Handlers.utils.hasMatchingTag("Action", "Infer-Response"),
    function(msg)
        local reference = msg.Tags["X-Reference"] or ""
        print(msg)

        if msg.Tags["Code"] then
            -- Update task status to failed
            if Tasks[reference] then
                local error_message = msg.Tags["Message"] or "Unknown error"
                Tasks[reference].status = "failed"
                Tasks[reference].error_message = error_message
                Tasks[reference].error_code = msg.Tags["Code"]
                Tasks[reference].endtime = os.time()
            end
            Send({
                device = 'patch@1.0',
                cache = {
                    tasks = {
                        [reference] = Tasks[reference] }
                }
            })
            return
        end
        Tasks[reference].response = msg.Data or ""
        Tasks[reference].status = "success"
        Tasks[reference].endtime = os.time()

        Send({
            device = 'patch@1.0',
            cache = {
                tasks = {
                    [reference] = Tasks[reference] }
            }
        })
    end
)

Handlers.add(
    "GetInferResponse",
    Handlers.utils.hasMatchingTag("Action", "GetInferResponse"),
    function(msg)
        local reference = msg.Tags["X-Reference"] or ""
        print(Tasks[reference])
        if Tasks[reference] then
            msg.reply({Data = json.encode(Tasks[reference])})
        else
            msg.reply({Data = "Task not found"}) -- if task not found, return error
        end
    end
)

-- Frontend workflow
-- 1. User input a prompt
-- 2. Generate a unique reference ID for the request
-- 3. Send the prompt to the backend
-- 4. Wait for the request ended, show a loading indicator
-- 5. Query the task status by Patch API(this is AO HyperBEAM's API for your process, not APUS service!):
--  `GET /{your_process_id}~process@1.0/now/cache/tasks/{your_process_id}-{reference}/serialize~json@1.0`
-- 6. display the response or error message
-- ```
-- {
--     prompt = "who are you?",
--     status = "success/failed",
--     reference = "123",
--     starttime = "1754705621248",
--     endtime = "1754705610148",
--     data = "{"attestation":"","result":"\nI am Gemma, an open-weights AI assistant."}",
--     error_code = "400", // has this field when the request failed
--     error_message = "Invalid request format" // has this field when the request failed
-- }
-- ```
-- 
-- Additional Notes:
-- - Ensure that the `APUS_ROUTER` is correctly set to your APUS service
-- - Ensure your are useing YOUR_PROCESS_ID in the frontend API calls
-- - You can check CREDITS BALANCE by querying the APUS_ROUTER Patch API
--  `GET /{APUS_ROUTER}~process@1.0/now/cache/credits/{your_process_id}/serialize~json@1.0`
-- http://72.46.85.207:8734/D0na6AspYVzZnZNa7lQHnBt_J92EldK_oFtEPLjIexo~process@1.0/now/cache/credits/sNWrdfUcR9kBpRPPPnJKFlel4j_z2rJ89PStNXITMto/serialize~json@1.0