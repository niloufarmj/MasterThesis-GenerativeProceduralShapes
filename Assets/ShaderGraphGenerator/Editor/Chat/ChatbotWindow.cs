using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

namespace ShaderGraphGenerator.Chat
{
    public class ChatbotWindow : EditorWindow
    {
        // ─── layout constants ────────────────────────────────────────────────
        private const float HEADER_H      = 52f;
        private const float BTN_H         = 36f;
        private const float INPUT_H       = 42f;
        private const float BUBBLE_MARGIN = 10f;
        private const float MAX_BUBBLE_W  = 0.78f; // fraction of window width

        // ─── colors ──────────────────────────────────────────────────────────
        private static readonly Color C_BG          = HEX("#1a1a1f");
        private static readonly Color C_HEADER      = HEX("#0f0f13");
        private static readonly Color C_BOTTOM      = HEX("#0f0f13");
        private static readonly Color C_USER        = HEX("#7c6fd4");
        private static readonly Color C_USER_TXT    = HEX("#ffffff");
        private static readonly Color C_BOT         = HEX("#2a2a32");
        private static readonly Color C_BOT_TXT     = HEX("#e8e8ec");
        private static readonly Color C_REPLY       = HEX("#2e2840");
        private static readonly Color C_REPLY_TXT   = HEX("#c4b8f8");
        private static readonly Color C_REPLY_BDR   = HEX("#5a4ea0");
        private static readonly Color C_ABORT       = HEX("#2a2a30");
        private static readonly Color C_ABORT_TXT   = HEX("#9090a0");
        private static readonly Color C_INPUT_BG    = HEX("#22222a");
        private static readonly Color C_INPUT_TXT   = HEX("#e8e8ec");
        private static readonly Color C_SEND        = HEX("#7c6fd4");
        private static readonly Color C_STATUS_TXT  = HEX("#7070a0");
        private static readonly Color C_RATING      = HEX("#3d3560");
        private static readonly Color C_RATING_TXT  = HEX("#c4b8f8");
        private static readonly Color C_ONLINE      = HEX("#3dba6a");
        private static readonly Color C_NAME        = HEX("#9988ee");
        private static readonly Color C_DIVIDER     = HEX("#2a2a35");

        // ─── cached textures (rebuilt once, reused) ──────────────────────────
        private Texture2D _txBg, _txHeader, _txBottom, _txDivider;
        private Texture2D _txUser, _txBot;
        private Texture2D _txReply, _txAbort, _txSend, _txInput;
        private Texture2D _txRating, _txRatingHov;
        private Texture2D _txReplyHov;
        private bool      _texReady;

        // ─── cached styles ───────────────────────────────────────────────────
        private GUIStyle _stBot, _stUser, _stReply, _stAbort;
        private GUIStyle _stInput, _stSend, _stRating;
        private GUIStyle _stStatus, _stLabel, _stName, _stOnline;
        private GUIStyle _stHeaderTitle;
        private bool     _stylesReady;

        // ─── runtime state ───────────────────────────────────────────────────
        private Vector2   _scroll;
        private string    _inputText      = "";
        private bool      _scrollBottom   = false;
        private bool      _focusInput     = false;
        private Texture2D _pendingThumb;

        private readonly Dictionary<string, Texture2D> _previewCache = new();

        // ─── menu ─────────────────────────────────────────────────────────────
        [MenuItem("Tools/ShaderGraph Generator/Chat UI")]
        public static void ShowWindow()
        {
            var w = GetWindow<ChatbotWindow>("Shader Expert");
            w.minSize = new Vector2(360, 560);
            ChatBridge.Start();
            if (ChatSession.History.Count == 0)
                ChatSession.AddBot("Hello! How can I assist you today?");
        }

        private void OnEnable()
        {
            ChatBridge.Start();
            if (ChatSession.History.Count == 0)
                ChatSession.AddBot("Hello! How can I assist you today?");
            _texReady    = false;
            _stylesReady = false;
        }

        private void OnDisable()
        {
            FreeTex();
        }

        private void Update()
        {
            bool generating = ChatSession.State == ChatState.Generating
                           || ChatSession.State == ChatState.Edit_Running
                           || ChatSession.State == ChatState.Animate_Running;
            if (generating) Repaint();
        }

        // ─── texture init ─────────────────────────────────────────────────────
        private void EnsureTextures()
        {
            if (_texReady && _txBg != null) return;
            _txBg        = Solid(C_BG);
            _txHeader    = Solid(C_HEADER);
            _txBottom    = Solid(C_BOTTOM);
            _txDivider   = Solid(C_DIVIDER);
            _txUser      = Solid(C_USER);
            _txBot       = Solid(C_BOT);
            _txReply     = Solid(C_REPLY);
            _txReplyHov  = Solid(Lighten(C_REPLY, 0.08f));
            _txAbort     = Solid(C_ABORT);
            _txSend      = Solid(C_SEND);
            _txInput     = Solid(C_INPUT_BG);
            _txRating    = Solid(C_RATING);
            _txRatingHov = Solid(Lighten(C_RATING, 0.12f));
            _texReady    = true;
            _stylesReady = false; // force style rebuild after textures
        }

        // ─── style init ───────────────────────────────────────────────────────
        private void EnsureStyles()
        {
            if (_stylesReady && _stBot != null) return;

            _stBot = new GUIStyle(GUI.skin.label)
            {
                wordWrap  = true,
                richText  = false,
                fontSize  = 12,
                padding   = new RectOffset(11, 11, 8, 8),
                margin    = new RectOffset(0, 0, 0, 0),
                alignment = TextAnchor.UpperLeft,
                normal    = { background = _txBot, textColor = C_BOT_TXT }
            };

            _stUser = new GUIStyle(_stBot)
            {
                alignment = TextAnchor.UpperLeft,
                normal    = { background = _txUser, textColor = C_USER_TXT }
            };

            _stReply = new GUIStyle(GUI.skin.button)
            {
                wordWrap  = true,
                fontSize  = 12,
                padding   = new RectOffset(14, 14, 9, 9),
                margin    = new RectOffset(10, 10, 3, 3),
                alignment = TextAnchor.MiddleLeft,
                normal    = { background = _txReply,    textColor = C_REPLY_TXT },
                hover     = { background = _txReplyHov, textColor = C_REPLY_TXT },
                active    = { background = _txReplyHov, textColor = Color.white  }
            };

            _stAbort = new GUIStyle(_stReply)
            {
                normal = { background = _txAbort, textColor = C_ABORT_TXT },
                hover  = { background = _txAbort, textColor = HEX("#c0c0cc") },
                active = { background = _txAbort, textColor = Color.white   }
            };

            _stInput = new GUIStyle(GUI.skin.textArea)
            {
                fontSize  = 12,
                wordWrap  = true,
                padding   = new RectOffset(12, 12, 10, 10),
                margin    = new RectOffset(0, 0, 0, 0),
                normal    = { background = _txInput, textColor = C_INPUT_TXT },
                focused   = { background = _txInput, textColor = C_INPUT_TXT },
                active    = { background = _txInput, textColor = C_INPUT_TXT }
            };

            _stSend = new GUIStyle(GUI.skin.button)
            {
                fontSize  = 17,
                padding   = new RectOffset(0, 2, 0, 0),
                margin    = new RectOffset(0, 0, 0, 0),
                alignment = TextAnchor.MiddleCenter,
                normal    = { background = _txSend, textColor = Color.white },
                hover     = { background = Solid(Lighten(C_SEND, 0.1f)), textColor = Color.white },
                active    = { background = _txSend, textColor = Color.white }
            };

            _stRating = new GUIStyle(GUI.skin.button)
            {
                fontSize  = 12,
                fontStyle = FontStyle.Bold,
                padding   = new RectOffset(0, 0, 0, 0),
                margin    = new RectOffset(2, 2, 0, 0),
                alignment = TextAnchor.MiddleCenter,
                normal    = { background = _txRating,    textColor = C_RATING_TXT },
                hover     = { background = _txRatingHov, textColor = Color.white   },
                active    = { background = _txRatingHov, textColor = Color.white   }
            };

            _stStatus = new GUIStyle(GUI.skin.label)
            {
                fontSize  = 11,
                fontStyle = FontStyle.Italic,
                padding   = new RectOffset(14, 0, 0, 0),
                normal    = { textColor = C_STATUS_TXT }
            };

            _stLabel = new GUIStyle(GUI.skin.label)
            {
                fontSize = 11,
                normal   = { textColor = C_STATUS_TXT }
            };

            _stName = new GUIStyle(GUI.skin.label)
            {
                fontSize  = 13,
                fontStyle = FontStyle.Bold,
                normal    = { textColor = C_NAME }
            };

            _stOnline = new GUIStyle(GUI.skin.label)
            {
                fontSize = 10,
                normal   = { textColor = C_ONLINE }
            };

            _stHeaderTitle = new GUIStyle(GUI.skin.label)
            {
                fontSize  = 13,
                fontStyle = FontStyle.Bold,
                normal    = { textColor = C_NAME }
            };

            _stylesReady = true;
        }

        // ─── OnGUI ────────────────────────────────────────────────────────────
        private void OnGUI()
        {
            EnsureTextures();
            EnsureStyles();

            float W = position.width;
            float H = position.height;

            var cfg    = ChatSession.GetConfig();
            float qH   = cfg.QuickReplies.Length * (BTN_H + 6f) + (cfg.QuickReplies.Length > 0 ? 10f : 0f);
            bool showInputRow = cfg.AllowFreeText || cfg.AllowFile || cfg.AllowImage || cfg.AllowMaterial;
            float botH = (cfg.ShowRating ? 48f : 0f)
                    + qH
                    + (showInputRow ? INPUT_H + 8f : 0f)
                    + (_pendingThumb != null ? 52f : 0f)
                    + 8f;
            float scrollH = Mathf.Max(40f, H - HEADER_H - botH);

            // ── background ──────────────────────────────────────────────────
            GUI.DrawTexture(new Rect(0, 0, W, H), _txBg);

            // ── header ──────────────────────────────────────────────────────
            DrawHeader(W);

            // ── message area ─────────────────────────────────────────────────
            var scrollRect = new Rect(0, HEADER_H, W, scrollH);
            GUI.DrawTexture(scrollRect, _txBg);

            GUILayout.BeginArea(scrollRect);
            _scroll = GUILayout.BeginScrollView(_scroll,
                false, false, GUIStyle.none, GUIStyle.none, GUIStyle.none,
                GUILayout.Width(W), GUILayout.Height(scrollH));

            GUILayout.Space(10);
            foreach (var msg in ChatSession.History)
                DrawMessage(msg, W);

            if (!string.IsNullOrEmpty(ChatBridge.StatusMsg))
            {
                GUILayout.Space(4);
                GUILayout.Label("  " + ChatBridge.StatusMsg + "  ◌", _stStatus);
                GUILayout.Space(4);
            }
            GUILayout.Space(16);
            GUILayout.EndScrollView();
            GUILayout.EndArea();

            if (_scrollBottom)
            {
                _scroll.y    = 999999f;
                _scrollBottom = false;
                Repaint();
            }

            // ── divider ──────────────────────────────────────────────────────
            float divY = HEADER_H + scrollH;
            GUI.DrawTexture(new Rect(0, divY, W, 1), _txDivider);

            // ── bottom panel ─────────────────────────────────────────────────
            GUI.DrawTexture(new Rect(0, divY + 1, W, H - divY - 1), _txBottom);
            GUILayout.BeginArea(new Rect(0, divY + 1, W, H - divY - 1));
            GUILayout.Space(6);

            if (cfg.ShowRating)        DrawRating();
            if (cfg.QuickReplies.Length > 0) DrawQuickReplies(cfg);
            if (_pendingThumb != null) DrawThumbRow();
            if (showInputRow)     DrawInputRow(cfg);

            GUILayout.EndArea();

            if (_focusInput) { GUI.FocusControl("ChatInput"); _focusInput = false; }
        }

        // ─── header ──────────────────────────────────────────────────────────
        private void DrawHeader(float W)
        {
            GUI.DrawTexture(new Rect(0, 0, W, HEADER_H), _txHeader);
            GUI.DrawTexture(new Rect(0, HEADER_H, W, 1), _txDivider);

            GUILayout.BeginArea(new Rect(0, 0, W, HEADER_H));
            GUILayout.BeginHorizontal();
            GUILayout.Space(12);

            // Avatar circle (drawn manually)
            Rect avatarRect = new Rect(12, 11, 30, 30);
            GUI.DrawTexture(avatarRect, _txUser);
            GUI.Label(avatarRect, "◈", new GUIStyle(GUI.skin.label)
            {
                fontSize  = 16,
                alignment = TextAnchor.MiddleCenter,
                normal    = { textColor = Color.white }
            });

            GUILayout.Space(38); // skip past avatar

            GUILayout.BeginVertical();
            GUILayout.Space(10);
            GUILayout.Label("Shader Expert", _stHeaderTitle);
            GUILayout.Label("● Online", _stOnline);
            GUILayout.EndVertical();

            GUILayout.FlexibleSpace();

            // Reset button
            var resetStyle = new GUIStyle(GUI.skin.button)
            {
                fontSize  = 14,
                padding   = new RectOffset(0, 0, 0, 0),
                normal    = { background = _txHeader, textColor = C_STATUS_TXT },
                hover     = { background = _txBot,    textColor = HEX("#ffffff") }
            };
            if (GUI.Button(new Rect(W - 38, 12, 28, 28), "↺", resetStyle))
            {
                ChatSession.Reset();
                ChatSession.AddBot("Hello! How can I assist you today?");
                _inputText    = "";
                _scrollBottom = true;
            }

            GUILayout.Space(40);
            GUILayout.EndHorizontal();
            GUILayout.EndArea();
        }

        // ─── message bubble ───────────────────────────────────────────────────
        private void DrawMessage(ChatMessage msg, float W)
        {
            bool isUser  = msg.Role == "user";
            var  style   = isUser ? _stUser : _stBot;
            float maxW   = W * MAX_BUBBLE_W;
            float pad    = BUBBLE_MARGIN;

            // preview image for bot messages
            if (!isUser && !string.IsNullOrEmpty(msg.ImageBase64))
            {
                if (!_previewCache.TryGetValue(msg.ImageBase64, out var tex))
                {
                    tex = LoadTex(msg.ImageBase64);
                    if (tex != null) _previewCache[msg.ImageBase64] = tex;
                }
                if (tex != null)
                {
                    float imgW = Mathf.Min(maxW - pad * 2, 220f);
                    float imgH = imgW * tex.height / Mathf.Max(1, tex.width);
                    GUILayout.BeginHorizontal();
                    GUILayout.Space(pad);
                    GUILayout.Box(tex, GUIStyle.none,
                        GUILayout.Width(imgW), GUILayout.Height(imgH));
                    GUILayout.EndHorizontal();
                    GUILayout.Space(3);
                }
            }

            if (string.IsNullOrEmpty(msg.Text)) return;

            // Measure text height
            float bubbleW = maxW;
            var   content = new GUIContent(msg.Text);
            float h       = style.CalcHeight(content, bubbleW);

            GUILayout.BeginHorizontal();
            if (isUser)
            {
                GUILayout.FlexibleSpace();
                GUILayout.Space(pad);
            }
            else
            {
                GUILayout.Space(pad);
            }

            // Draw bubble background + text
            Rect bRect = GUILayoutUtility.GetRect(content, style,
                GUILayout.Width(bubbleW), GUILayout.Height(h));
            GUI.DrawTexture(bRect, isUser ? _txUser : _txBot);
            GUI.Label(bRect, content, style);

            if (!isUser)
            {
                GUILayout.FlexibleSpace();
                GUILayout.Space(pad);
            }
            GUILayout.EndHorizontal();
            GUILayout.Space(5);
        }

        // ─── rating row ───────────────────────────────────────────────────────
        private void DrawRating()
        {
            GUILayout.BeginHorizontal();
            GUILayout.Space(10);
            GUILayout.Label("Rate result:", _stLabel, GUILayout.Width(72), GUILayout.Height(BTN_H - 10));
            for (int i = 1; i <= 10; i++)
            {
                if (GUILayout.Button(i.ToString(), _stRating,
                    GUILayout.Width(28), GUILayout.Height(28)))
                    Send(i.ToString());
            }
            GUILayout.Space(10);
            GUILayout.EndHorizontal();
            GUILayout.Space(6);
        }

        // ─── quick replies ────────────────────────────────────────────────────
        private void DrawQuickReplies(StateConfig cfg)
        {
            foreach (var qr in cfg.QuickReplies)
            {
                bool abort = qr.Value == "abort";
                var  st    = abort ? _stAbort : _stReply;
                if (GUILayout.Button(qr.Label, st, GUILayout.Height(BTN_H)))
                    Send(qr.Value, qr.Label);
            }
            GUILayout.Space(4);
        }

        // ─── thumb row ────────────────────────────────────────────────────────
        private void DrawThumbRow()
        {
            GUILayout.BeginHorizontal();
            GUILayout.Space(10);
            float tw = 44f;
            float th = tw * _pendingThumb.height / Mathf.Max(1, _pendingThumb.width);
            GUILayout.Box(_pendingThumb, GUIStyle.none,
                GUILayout.Width(tw), GUILayout.Height(th));
            GUILayout.Space(6);
            GUILayout.Label("Image attached", new GUIStyle(_stLabel) { padding = new RectOffset(0,0,4,0) });
            GUILayout.FlexibleSpace();
            if (GUILayout.Button("✕", new GUIStyle(_stAbort)
                { fontSize = 11, padding = new RectOffset(0,0,0,0) },
                GUILayout.Width(22), GUILayout.Height(22)))
            {
                Object.DestroyImmediate(_pendingThumb);
                _pendingThumb = null;
                ChatSession.PendingImageBase64 = null;
            }
            GUILayout.Space(10);
            GUILayout.EndHorizontal();
            GUILayout.Space(2);
        }

        // ─── input row ────────────────────────────────────────────────────────
        private void DrawInputRow(StateConfig cfg)
        {
            GUILayout.BeginHorizontal();
            GUILayout.Space(10);

            
            if (cfg.AllowMaterial)
            {
                var matBtnStyle = new GUIStyle(_stAbort)
                {
                    fontSize  = 12,
                    alignment = TextAnchor.MiddleCenter,
                    padding   = new RectOffset(0, 0, 0, 0),
                    normal    = { background = _txInput,
                                textColor  = ChatSession.PendingMaterialPath != null
                                            ? C_ONLINE : C_STATUS_TXT }
                };
                if (GUILayout.Button("📎", matBtnStyle,
                    GUILayout.Width(INPUT_H - 2), GUILayout.Height(INPUT_H - 2)))
                    PickMaterialFile();
                GUILayout.Space(4);
            }

            if (cfg.AllowImage)
            {
                var imgStyle = new GUIStyle(_stAbort)
                {
                    fontSize  = 14,
                    alignment = TextAnchor.MiddleCenter,
                    padding   = new RectOffset(0, 0, 0, 0),
                    normal    = { background = _txInput,
                                  textColor  = _pendingThumb != null
                                               ? C_ONLINE : C_STATUS_TXT }
                };
                if (GUILayout.Button("⊞", imgStyle,
                    GUILayout.Width(INPUT_H - 2), GUILayout.Height(INPUT_H - 2)))
                    PickImage();
                GUILayout.Space(4);
            }

            if (cfg.AllowFile)
            {
                var fileBtnStyle = new GUIStyle(_stAbort)
                {
                    fontSize  = 12,
                    alignment = TextAnchor.MiddleCenter,
                    padding   = new RectOffset(0, 0, 0, 0),
                    normal    = { background = _txInput,
                                textColor  = ChatSession.PendingHLSLPath != null
                                            ? C_ONLINE : C_STATUS_TXT }
                };
                if (GUILayout.Button("📎", fileBtnStyle,
                    GUILayout.Width(INPUT_H - 2), GUILayout.Height(INPUT_H - 2)))
                    PickHLSLFile();
                GUILayout.Space(4);
            }


            if (cfg.AllowFreeText)
            {
                GUI.SetNextControlName("ChatInput");
                _inputText = GUILayout.TextArea(_inputText, _stInput,
                    GUILayout.MinHeight(INPUT_H - 2), GUILayout.ExpandWidth(true), GUILayout.ExpandHeight(false));

                bool canSend = !string.IsNullOrWhiteSpace(_inputText) || ChatSession.PendingImageBase64 != null;

                // Enter key sends
                if (Event.current.type == EventType.KeyDown &&
                    Event.current.keyCode == KeyCode.Return  &&
                    canSend)
                {
                    DoSendText();
                    Event.current.Use();
                }

                GUILayout.Space(4);
                if (GUILayout.Button("▶", _stSend,
                GUILayout.Width(INPUT_H - 2), GUILayout.Height(INPUT_H - 2), GUILayout.ExpandWidth(false)) &&
                canSend)
                {
                    DoSendText();
                }
            }
            else
            {
                // Use the custom placeholder defined in ChatSession (e.g. "Attach file.")
                GUILayout.Label(cfg.Placeholder, 
                    new GUIStyle(_stStatus) { padding = new RectOffset(4,0,10,0) });
                GUILayout.FlexibleSpace();
            }


            GUILayout.Space(10);
            GUILayout.EndHorizontal();
            GUILayout.Space(6);
        }

        private void DoSendText()
        {
            string t  = _inputText.Trim();
            _inputText = "";
            Send(t);  // state machine consumes PendingImageBase64 here
            if (_pendingThumb != null)
            {
                Object.DestroyImmediate(_pendingThumb);
                _pendingThumb = null;
            }
            ChatSession.PendingImageBase64 = null;
        }

        // ─── image picker ─────────────────────────────────────────────────────
        private void PickImage()
        {
            string path = EditorUtility.OpenFilePanel("Select reference image", "", "png,jpg,jpeg");
            if (string.IsNullOrEmpty(path)) return;
            var bytes = System.IO.File.ReadAllBytes(path);
            ChatSession.PendingImageBase64 = System.Convert.ToBase64String(bytes);
            if (_pendingThumb != null) Object.DestroyImmediate(_pendingThumb);
            _pendingThumb = new Texture2D(2, 2);
            _pendingThumb.LoadImage(bytes);
            Repaint();
        }

        // ─── send ─────────────────────────────────────────────────────────────
        private void Send(string value, string displayText = null)
        {
            ChatBridgeLocal.ProcessMessage(value, displayText);
            _scrollBottom = true;
            _focusInput   = true;
            Repaint();
        }

        // ─── texture helpers ──────────────────────────────────────────────────
        private static Texture2D Solid(Color c)
        {
            var t = new Texture2D(1, 1, TextureFormat.RGBA32, false);
            t.SetPixel(0, 0, c);
            t.Apply();
            return t;
        }

        private static Color Lighten(Color c, float amt) =>
            new Color(
                Mathf.Clamp01(c.r + amt),
                Mathf.Clamp01(c.g + amt),
                Mathf.Clamp01(c.b + amt),
                c.a);

        private static Color HEX(string hex)
        {
            hex = hex.TrimStart('#');
            float r = System.Convert.ToInt32(hex.Substring(0, 2), 16) / 255f;
            float g = System.Convert.ToInt32(hex.Substring(2, 2), 16) / 255f;
            float b = System.Convert.ToInt32(hex.Substring(4, 2), 16) / 255f;
            float a = hex.Length >= 8
                ? System.Convert.ToInt32(hex.Substring(6, 2), 16) / 255f
                : 1f;
            return new Color(r, g, b, a);
        }

        private static Texture2D LoadTex(string pathOrBase64)
        {
            if (System.IO.File.Exists(pathOrBase64))
            {
                var t = new Texture2D(2, 2);
                t.LoadImage(System.IO.File.ReadAllBytes(pathOrBase64));
                return t;
            }
            try
            {
                var t = new Texture2D(2, 2);
                t.LoadImage(System.Convert.FromBase64String(pathOrBase64));
                return t;
            }
            catch { return null; }
        }

        private void FreeTex()
        {
            void D(Texture2D t) { if (t) Object.DestroyImmediate(t); }
            D(_txBg); D(_txHeader); D(_txBottom); D(_txDivider);
            D(_txUser); D(_txBot); D(_txReply); D(_txReplyHov);
            D(_txAbort); D(_txSend); D(_txInput);
            D(_txRating); D(_txRatingHov);
            _texReady = _stylesReady = false;
        }

        private void PickHLSLFile()
        {
            string path = EditorUtility.OpenFilePanel("Select HLSL file", "", "hlsl");
            if (string.IsNullOrEmpty(path)) return;
            ChatSession.PendingHLSLPath = path;
            string fileName = System.IO.Path.GetFileName(path);
            ChatBridgeLocal.ProcessMessage("file_attached", $"[file: {fileName}]");
            _scrollBottom = true;
            Repaint();
        }

        private void PickMaterialFile()
        {
            string path = EditorUtility.OpenFilePanel("Select Material", "Assets", "mat");
            if (string.IsNullOrEmpty(path)) return;
            ChatSession.PendingMaterialPath = path;
            string fileName = System.IO.Path.GetFileName(path);
            ChatBridgeLocal.ProcessMessage("material_attached", $"[file: {fileName}]");
            _scrollBottom = true;
            Repaint();
        }
    }
}