# setup_n8n.ps1 - Crea el workflow de doblaje en n8n automaticamente
# Solo necesitas: tu API key de n8n

Set-ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SETUP N8N - Workflow de Doblaje" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Necesito tu API Key de n8n." -ForegroundColor Yellow
Write-Host "Para obtenerla:" -ForegroundColor Yellow
Write-Host "  1. Ve a localhost:5678" -ForegroundColor White
Write-Host "  2. Click en el engranaje (Settings) abajo a la izquierda" -ForegroundColor White
Write-Host "  3. Click en 'API'" -ForegroundColor White
Write-Host "  4. Click en 'Create an API key'" -ForegroundColor White
Write-Host "  5. Copia la key y pegala aqui" -ForegroundColor White
Write-Host ""

$API_KEY = Read-Host "Pega tu API Key aqui"

if ([string]::IsNullOrWhiteSpace($API_KEY)) {
    Write-Host "ERROR: No pusiste API key" -ForegroundColor Red
    exit 1
}

$N8N_URL = "http://localhost:5678"
$HEADERS = @{ "X-N8N-API-KEY" = $API_KEY; "Content-Type" = "application/json" }

# Verificar conexion
Write-Host "`nVerificando conexion con n8n..." -ForegroundColor Yellow
try {
    $test = Invoke-RestMethod -Uri "$N8N_URL/api/v1/workflows" -Headers $HEADERS -Method Get
    Write-Host "  Conectado a n8n OK" -ForegroundColor Green
} catch {
    Write-Host "  ERROR: No se pudo conectar. Asegurate de que n8n este corriendo." -ForegroundColor Red
    Write-Host "  En otra PowerShell corre: n8n start" -ForegroundColor Yellow
    exit 1
}

# --- CREAR WORKFLOW ---
Write-Host "`nCreando workflow de doblaje..." -ForegroundColor Yellow

$PROJECT_DIR = "$HOME\IA\ai_video_dubbing" -replace '\\', '\\\\'

$WORKFLOW_JSON = @"
{
  "name": "Doblar Video Automatico",
  "nodes": [
    {
      "parameters": {},
      "id": "trigger",
      "name": "Click para Doblar",
      "type": "n8n-nodes-base.manualTrigger",
      "typeVersion": 1,
      "position": [220, 300]
    },
    {
      "parameters": {
        "jsCode": "// CONFIGURA AQUI:\\n// Cambia video_url por el link que quieras doblar\\nreturn [{\\n  json: {\\n    video_url: 'https://youtu.be/eOUfemUXMxk',\\n    voice: 'es-ES-AlvaroNeural',\\n    output_name: 'video_doblado',\\n    project_dir: '$PROJECT_DIR'\\n  }\\n}];"
      },
      "id": "config",
      "name": "1. Config - Pon tu URL aqui",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [460, 300]
    },
    {
      "parameters": {
        "jsCode": "const { execSync } = require('child_process');\\nconst data = \$input.first().json;\\nconst dir = data.project_dir.replace(/\\\\\\\\\\\\\\\\/g, '\\\\\\\\');\\n\\ntry {\\n  const cmd = 'cd \"' + dir + '\" && python run_pipeline.py \"' + data.video_url + '\" --voice ' + data.voice + ' --output ' + data.output_name;\\n  console.log('Ejecutando: ' + cmd);\\n  const result = execSync(cmd, { encoding: 'utf-8', timeout: 1800000, maxBuffer: 50 * 1024 * 1024 });\\n  console.log(result);\\n  return [{ json: { success: true, output: result.substring(result.length - 500), video: dir + '\\\\\\\\output\\\\\\\\' + data.output_name + '.mp4' } }];\\n} catch(e) {\\n  return [{ json: { success: false, error: e.message.substring(0, 500) } }];\\n}"
      },
      "id": "pipeline",
      "name": "2. Correr Pipeline Completo",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [740, 300]
    },
    {
      "parameters": {
        "jsCode": "const data = \$input.first().json;\\nif (data.success) {\\n  return [{ json: { mensaje: 'VIDEO DOBLADO LISTO!', archivo: data.video, output: data.output } }];\\n} else {\\n  return [{ json: { mensaje: 'ERROR en el pipeline', error: data.error } }];\\n}"
      },
      "id": "result",
      "name": "3. Resultado",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [1020, 300]
    }
  ],
  "connections": {
    "Click para Doblar": {
      "main": [[{ "node": "1. Config - Pon tu URL aqui", "type": "main", "index": 0 }]]
    },
    "1. Config - Pon tu URL aqui": {
      "main": [[{ "node": "2. Correr Pipeline Completo", "type": "main", "index": 0 }]]
    },
    "2. Correr Pipeline Completo": {
      "main": [[{ "node": "3. Resultado", "type": "main", "index": 0 }]]
    }
  },
  "settings": { "executionOrder": "v1" }
}
"@

try {
    $response = Invoke-RestMethod -Uri "$N8N_URL/api/v1/workflows" -Headers $HEADERS -Method Post -Body $WORKFLOW_JSON
    $WORKFLOW_ID = $response.id
    Write-Host "  Workflow creado! ID: $WORKFLOW_ID" -ForegroundColor Green
} catch {
    Write-Host "  Error creando workflow: $_" -ForegroundColor Red
    Write-Host "  Intentando con formato alternativo..." -ForegroundColor Yellow

    # Guardar JSON y importar manualmente
    $WORKFLOW_JSON | Out-File -FilePath "$HOME\Downloads\workflow_auto.json" -Encoding UTF8
    Write-Host "  Workflow guardado en Downloads\workflow_auto.json" -ForegroundColor Yellow
    Write-Host "  Importalo manualmente en n8n: Ctrl+O > selecciona el archivo" -ForegroundColor Yellow
}

# --- GUARDAR API KEY para uso futuro ---
$API_KEY | Out-File -FilePath "$HOME\IA\.n8n_api_key" -Encoding UTF8
Write-Host "`n  API Key guardada en $HOME\IA\.n8n_api_key" -ForegroundColor Green

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  LISTO! Ahora:" -ForegroundColor Green
Write-Host "  1. Ve a localhost:5678" -ForegroundColor White
Write-Host "  2. Abre el workflow 'Doblar Video Automatico'" -ForegroundColor White
Write-Host "  3. Click en 'Test workflow'" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Abrir n8n en el navegador
Start-Process "http://localhost:5678"

Read-Host "Presiona Enter para cerrar"
