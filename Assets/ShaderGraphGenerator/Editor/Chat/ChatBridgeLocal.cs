namespace ShaderGraphGenerator.Chat
{
    /// <summary>
    /// Direct (non-HTTP) entry point for the IMGUI window.
    /// Mirrors what the browser would POST to /send.
    /// </summary>
    public static class ChatBridgeLocal
    {
        /// <param name="value">The value processed by the state machine.</param>
        /// <param name="displayText">Human-readable label shown in the user bubble.
        /// Defaults to <paramref name="value"/> when null.</param>
        public static void ProcessMessage(string value, string displayText = null)
        {
            string display = displayText ?? value;
            string json = "{\"message\":\"" + Escape(value)   + "\""
                        + ",\"display\":\"" + Escape(display) + "\"}";
            ChatBridge.HandleSend(json);
        }

        private static string Escape(string s) =>
            s?.Replace("\\", "\\\\").Replace("\"", "\\\"") ?? "";
    }
}
