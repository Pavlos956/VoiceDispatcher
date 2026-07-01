$json = Get-Content -Raw "sa-key.json"
$env:FIREBASE_SERVICE_ACCOUNT = $json
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$json" --project-ref oogjreozyrdcprechvnj
