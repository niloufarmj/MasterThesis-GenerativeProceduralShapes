using System.Collections.Generic;

namespace ShaderGraphGenerator.Chat
{
    public enum ChatState
    {
        MainMenu,
        NewShape_InputMode,
        NewShape_Image,
        NewShape_Text,
        Generating,
        Reviewing,
        PostGen,
        Edit_Describe,
        Edit_Running,
        Animate_Attach,
        Animate_Describe,
        Animate_Running,
        Effect_Attach,
        Effect_Pick,
        HLSL_Attach,
        HLSL_Running,
        HLSL_Done,
        Explain,
        Contact_Name,
        Contact_Intent,
        Contact_Email,
        Contact_Message,
        Done
    }

    public class QuickReply
    {
        public string Label;
        public string Value;
    }

    public class ChatMessage
    {
        public string Role;          // "bot" or "user"
        public string Text;
        public string ImageBase64;   // optional — preview image path or base64
    }

    public static class ChatSession
    {
        public static ChatState        State   = ChatState.MainMenu;
        public static List<ChatMessage> History = new List<ChatMessage>();

        public static string PendingImageBase64 = null;
        public static string PendingPrompt      = null;
        public static int    LastScore          = -1;
        public static string PendingHLSLPath = null;
        public static string PendingMaterialPath = null;

        // ── public API ──────────────────────────────────────────────────────

        public static void Reset()
        {
            State               = ChatState.MainMenu;
            History             = new List<ChatMessage>();
            PendingImageBase64  = null;
            PendingPrompt       = null;
            LastScore           = -1;
            PendingHLSLPath     = null;
            PendingMaterialPath = null;
        }

        public static void AddBot(string text, string imageBase64 = null)
        {
            History.Add(new ChatMessage { Role = "bot", Text = text, ImageBase64 = imageBase64 });
        }

        public static void AddUser(string text)
        {
            History.Add(new ChatMessage { Role = "user", Text = text });
        }

        /// <summary>Returns the quick replies and input config for the current state.</summary>
        public static StateConfig GetConfig()
        {
            switch (State)
            {
                // ── main menu ────────────────────────────────────────────────
                case ChatState.MainMenu:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "I want a new 2D shape with shader.",                         Value = "new_shape"  },
                            new QuickReply { Label = "I have a shape (material) and I want to edit it.",           Value = "edit"       },
                            new QuickReply { Label = "I have a shape and I want to animate it.",                   Value = "animate"    },
                            new QuickReply { Label = "I have a material and I want to add a special effect to it.", Value = "effect"     },
                            new QuickReply { Label = "I have a hlsl file and want to turn it into material.",      Value = "hlsl"       },
                            new QuickReply { Label = "Explain to me, how does this work?",                         Value = "explain"    },
                            new QuickReply { Label = "I want to contact the developer.",                           Value = "contact"    },
                        }
                    };

                case ChatState.HLSL_Attach:
                return new StateConfig
                    {
                        AllowFile   = true,
                        Placeholder = "Attach file.",
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "I want to do something else.", Value = "back" }
                        }
                    };

                case ChatState.HLSL_Running:
                    return new StateConfig
                    {
                        AllowAbort   = true,
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "Abort the process.", Value = "abort" }
                        }
                    };

                // ── new shape: pick mode ─────────────────────────────────────
                case ChatState.NewShape_InputMode:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "I have an image reference.",           Value = "image" },
                            new QuickReply { Label = "I want to explain the shape in text.", Value = "text"  },
                            new QuickReply { Label = "I want to do something else.",         Value = "back"  },
                        }
                    };

                // ── new shape: image input ───────────────────────────────────
                case ChatState.NewShape_Image:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        AllowImage    = true,
                        Placeholder   = "Describe editable features (optional)…",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "I want to explain the shape in text instead.", Value = "switch_text" },
                            new QuickReply { Label = "I want to do something else.",                 Value = "back"        },
                        }
                    };

                // ── new shape: text input ────────────────────────────────────
                case ChatState.NewShape_Text:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        Placeholder   = "Describe your 2D shape fully…",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "I have an image reference instead.", Value = "switch_image" },
                            new QuickReply { Label = "I want to do something else.",       Value = "back"         },
                        }
                    };

                // ── generating / running states ──────────────────────────────
                case ChatState.Generating:
                case ChatState.Edit_Running:
                case ChatState.Animate_Running:
                    return new StateConfig
                    {
                        AllowAbort   = true,
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "Abort the process.", Value = "abort" }
                        }
                    };

                // ── review ───────────────────────────────────────────────────
                case ChatState.Reviewing:
                    return new StateConfig
                    {
                        ShowRating   = true,
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "Abort the process.", Value = "abort" }
                        }
                    };

                // ── post-generation menu ─────────────────────────────────────
                case ChatState.PostGen:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "I want to edit something about this shape.",         Value = "edit"   },
                            new QuickReply { Label = "I want to animate it.",                              Value = "animate"},
                            new QuickReply { Label = "I want to add an effect (for example pixelation).", Value = "effect" },
                            new QuickReply { Label = "I want to do something else.",                      Value = "back"   },
                        }
                    };

                // ── edit ─────────────────────────────────────────────────────
                case ChatState.Edit_Describe:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        Placeholder   = "Explain what changes you need…",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "I want to do something else.", Value = "back" }
                        }
                    };

                // ── animate ──────────────────────────────────────────────────
                case ChatState.Animate_Attach:
                    return new StateConfig
                    {
                        AllowMaterial = true, // We'll use this in ChatbotWindow to show the picker
                        Placeholder   = "attach material.",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "I want to do something else.", Value = "back" }
                        }
                    };
                
                case ChatState.Animate_Describe:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        Placeholder   = "Explain the animation you want…",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "I want to do something else.", Value = "back" }
                        }
                    };

                // ── effect picker ────────────────────────────────────────────
                case ChatState.Effect_Pick:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "Pixelation.",              Value = "effect_pixel" },
                            new QuickReply { Label = "I want to do something else.", Value = "back"     },
                        }
                    };

                case ChatState.HLSL_Done:
                return new StateConfig
                {
                    QuickReplies = new[]
                    {
                        new QuickReply { Label = "I want to add a special effect to it.", Value = "effect" },
                        new QuickReply { Label = "Thanks, I'm done!",                     Value = "back"   },
                    }
                };

                // ── effect: attach material (main-menu entry) ────────────────
                case ChatState.Effect_Attach:
                    return new StateConfig
                    {
                        AllowMaterial = true,
                        Placeholder   = "Attach material.",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "I want to do something else.", Value = "back" }
                        }
                    };

                // ── explain ──────────────────────────────────────────────────
                case ChatState.Explain:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "Thanks for the info!", Value = "back" }
                        }
                    };

                // ── contact: ask name ────────────────────────────────────────
                case ChatState.Contact_Name:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        Placeholder   = "Type your name here…"
                    };

                // ── contact: after intro — skip or send message ──────────────
                case ChatState.Contact_Intent:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "I want to send a message to you.",              Value = "contact_send"     },
                            new QuickReply { Label = "Thanks for the info, I just wanted to connect.", Value = "contact_skip_all" },
                        }
                    };

                // ── contact: ask email ───────────────────────────────────────
                case ChatState.Contact_Email:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        Placeholder   = "Type your email address here…",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "Thanks for the info, I just wanted to connect.", Value = "contact_skip" }
                        }
                    };

                // ── contact: ask message ─────────────────────────────────────
                case ChatState.Contact_Message:
                    return new StateConfig
                    {
                        AllowFreeText = true,
                        Placeholder   = "Type your message here…",
                        QuickReplies  = new[]
                        {
                            new QuickReply { Label = "Thanks for the info, I just wanted to connect.", Value = "contact_skip" }
                        }
                    };

                // ── fallback ─────────────────────────────────────────────────
                default:
                    return new StateConfig
                    {
                        QuickReplies = new[]
                        {
                            new QuickReply { Label = "Go back to main menu.", Value = "back" }
                        }
                    };
            }
        }
    }

    public class StateConfig
    {
        public QuickReply[] QuickReplies = new QuickReply[0];
        public bool         AllowFreeText = false;
        public bool         AllowImage    = false;
        public bool         AllowAbort    = false;
        public bool         AllowFile     = false;
        public bool         AllowMaterial = false;
        public bool         ShowRating    = false;
        public string       Placeholder   = "Choose one of the options above.";
    }
}