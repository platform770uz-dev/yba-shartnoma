(() => {
  "use strict";
  const cfg=window.YBA_CONFIG||{},$=id=>document.getElementById(id);
  const client=window.supabase&&cfg.supabase_url&&cfg.supabase_publishable_key?window.supabase.createClient(cfg.supabase_url,cfg.supabase_publishable_key):null;
  function message(text,error=false){const el=$("adminMessage");el.textContent=text;el.className="notice"+(error?" error":"");el.hidden=!text}
  function signedIn(){ $("loginPanel").hidden=true;$("adminPanel").hidden=false;loadContracts() }
  async function loadContracts(){
    $("contractsRows").replaceChildren();$("emptyList").hidden=true;
    const {data,error}=await client.rpc("admin_list_contracts");
    if(error){message("Bu hisobga administrator huquqi berilmagan yoki roʻyxatni yuklab boʻlmadi.",true);return}
    if(!data?.length){$("emptyList").hidden=false;return}
    for(const row of data){
      const tr=document.createElement("tr"),values=[row.contract_number,row.status==="signed"?"Imzolangan":"Kutilmoqda",row.parent_name||"—",row.parent_phone||"—",new Date(row.signed_at||row.created_at).toLocaleString("uz-UZ",{timeZone:"Asia/Tashkent"})];
      for(const value of values){const td=document.createElement("td");td.textContent=value;tr.append(td)}
      const td=document.createElement("td");if(row.status==="signed"&&row.pdf_path){const button=document.createElement("button");button.type="button";button.className="button secondary table-button";button.textContent="PDF yuklab olish";button.addEventListener("click",async()=>{button.disabled=true;const result=await client.storage.from(cfg.contract_bucket||"shartnomalar").createSignedUrl(row.pdf_path,300,{download:"Shartnoma_YBA_"+row.contract_number+".pdf"});button.disabled=false;if(result.error){message("PDF havolasini yaratib boʻlmadi.",true);return}window.open(result.data.signedUrl,"_blank","noopener,noreferrer")});td.append(button)}else td.textContent="—";tr.append(td);$("contractsRows").append(tr)
    }
  }
  $("loginButton").addEventListener("click",async()=>{if(!client){message("Supabase sozlamalari topilmadi.",true);return}const button=$("loginButton");button.disabled=true;const {error}=await client.auth.signInWithPassword({email:$("email").value.trim(),password:$("password").value});button.disabled=false;if(error){message("Kirish amalga oshmadi. Elektron pochta va parolni tekshiring.",true);return}$("password").value="";message("");signedIn()});
  $("password").addEventListener("keydown",e=>{if(e.key==="Enter")$("loginButton").click()});
  $("logoutButton").addEventListener("click",async()=>{await client.auth.signOut();$("adminPanel").hidden=true;$("loginPanel").hidden=false;message("Tizimdan chiqdingiz.")});
  $("refreshButton").addEventListener("click",loadContracts);
  $("createButton").addEventListener("click",async()=>{const price=Number($("monthlyPrice").value);if(!Number.isSafeInteger(price)||price<1||price>1000000000){message("Oylik toʻlovni butun soʻmda kiriting.",true);return}const button=$("createButton");button.disabled=true;const {data,error}=await client.rpc("admin_create_contract",{p_monthly_price:price});button.disabled=false;if(error||!data?.[0]){message("Yangi shartnoma yaratilmadi. Administrator huquqini tekshiring.",true);return}const row=data[0],url=new URL("./",location.href);url.search="";url.hash="";url.searchParams.set("c",row.contract_id);$("contractLink").href=url.href;$("contractLink").textContent=url.href;$("createdLink").hidden=false;message("Shartnoma havolasi va raqami yaratildi.");try{await QRCode.toCanvas($("qrCanvas"),url.href,{width:256,margin:2,errorCorrectionLevel:"M"})}catch(_){message("Havola yaratildi, ammo QR-kod tayyorlanmadi.",true)}await loadContracts()});
  $("downloadQr").addEventListener("click",()=>{const a=document.createElement("a");a.href=$("qrCanvas").toDataURL("image/png");a.download="YBA_shartnoma_QR.png";a.click()});
  if(client)client.auth.getSession().then(({data})=>{if(data.session)signedIn()});else message("Supabase sozlamalari topilmadi.",true);
})();
