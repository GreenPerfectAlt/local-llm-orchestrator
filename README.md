# Local LLM Orchestrator (CLI)

![Status](https://img.shields.io/badge/Status-In%20Development-yellow)

An advanced batch automation tool for managing the full stack of local Large Language Models (LLM).
It orchestrates the connection between inference backends (**Llama.cpp**, **KoboldCPP**) and popular frontends (**SillyTavern**, **RisuAI**).

> ⚠️ **Note:** This project is currently in the **Testing / POC (Proof of Concept)** phase. Features are being actively debugged and optimized.

## 🚀 Key Features

* **Full Stack Orchestration:** Seamlessly launches the API backend and connects it to the user's preferred frontend interface (SillyTavern, RisuAI, Kobold Lite).
* **Automated Environment:** Manages process lifecycles, cleanup, and port conflicts.
* **Model Scanning:** Auto-detects `.gguf` models and `.zim` datasets recursively.
* **Smart Inference Config:** Applies advanced sampling settings (`Dynatemp`, `DRY`, `Min-P`) optimized for CPU performance.
* **RAG Capability:** Includes a "Chat with File" mode for analyzing local documents via CLI.

## 🛠 Tech Stack

* **Scripting:** Windows Batch / Shell
* **Inference Engines:** Llama.cpp, KoboldCPP
* **Supported Frontends:** SillyTavern (Node.js), RisuAI
* **Data Layer:** Kiwix (Offline Wikipedia integration)

## 🚧 Current Status & Roadmap

* [x] Core CLI Logic & Process Management
* [x] Llama.cpp & KoboldCPP Integration
* [ ] Advanced Error Handling
* [ ] Performance Optimization for large contexts

## 🔧 How it works

1. The script scans for models and configurations in the directory.
2. Starts the backend server (API).
3. Launches the selected frontend application.
4. Handles clean termination of all related processes upon exit.
