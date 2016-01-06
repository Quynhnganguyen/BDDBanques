create or replace function ajout_moyen_paiement(IBANcompte int, BICcompte t_compte.BIC%type, IDmoyen int) returns void as $$
begin
	perform * from t_compte where IBANcompte=IBAN and BICcompte = BIC and actif=true;
	if not found then
		RAISE exception 'compte inexistant';
	end if;
	
	perform * from t_moyen_paiement where id=IDmoyen;
	if not found then
		RAISE exception 'moyen de paiement inexistant';
	end if;

	perform * from t_avantages where IBANcompte=compte_IBAN and BICcompte = compte_BIC and moyen_paiement_id=IDmoyen;
	if found then
		RAISE exception 'Ce compte possede deja ce moyen de paiement';
	end if;
	insert into t_avantages values(IDmoyen, IBANcompte, BICcompte);

end
$$ language 'plpgsql';




create or replace function suppression_moyen_paiement(IBANcompte int, BICcompte t_compte.BIC%type, IDmoyen int) returns void as $$
begin
	perform * from t_avantages, t_compte where IBANcompte=compte_IBAN and compte_IBAN=IBAN and BICcompte = compte_BIC and compte_BIC=BIC and moyen_paiement_id=IDmoyen and actif=true;
	if not found then
		RAISE exception 'couple IBAN/BIC/moyen de paiement inexistant';
	end if;
	delete from t_avantages where IBANcompte=compte_IBAN and BICcompte = compte_BIC and moyen_paiement_id=IDmoyen;
end
$$ language 'plpgsql';




create or replace function virement_unique_intra(IBANdebiteur int, IBANcrediteur int, BICdebiteur t_compte.BIC%type, BICcrediteur t_compte.BIC%type, montantOp float, IDmoyen int, indications varchar(40)) returns void as $$
declare
	clientdebiteur int;
	clientcrediteur int;
	maxdebit float;
	coutOp float := 2.0;
begin
	select proprietaire into clientdebiteur from t_compte_vue, t_compte 
		where t_compte_vue.IBAN = IBANdebiteur and t_compte_vue.BIC = BICdebiteur and actif=true;
	if clientdebiteur is null then 
		raise exception 'compte debiteur inexistant';
	end if;

	select proprietaire into clientcrediteur from t_compte_vue, t_compte 
		where t_compte_vue.IBAN = IBANcrediteur and t_compte_vue.BIC = BICcrediteur and actif=true;
	if clientcrediteur is null then 
		raise exception 'compte crediteur inexistant';
	end if;

	perform * from t_avantages where IBANdebiteur=compte_IBAN and BICdebiteur = compte_BIC and moyen_paiement_id=IDmoyen;
	if not found then
		RAISE exception 'couple IBAN/BIC/moyen de paiement inexistant';
	end if;
	select (solde + decouvert_autorise + depassement_decouvert) into maxdebit from t_compte 
		where IBAN = IBANdebiteur and BIC = BICdebiteur;

	if (maxdebit < montantOp) then
		perform * from t_cheque where id = IDmoyen;
		if found then
			perform interdit_bancaire(clientdebiteur, 'Cheque sans provisions'); 
		end if;
		raise exception 'solde insuffisant';
	end if;
	
	if (clientdebiteur <> clientcrediteur) then
		update t_compte set solde = solde - coutOp where BICdebiteur = BIC and IBANdebiteur = IBAN;
		update t_compte set solde = solde + coutOp where 'Banque' = BIC and 0 = IBAN;
	else
		coutOp:=0;
	end if;

	update t_compte set solde = solde - montantOp where BICdebiteur = BIC and IBANdebiteur = IBAN; 
	update t_compte set solde = solde + montantOp where BICcrediteur = BIC and IBANcrediteur = IBAN;

	insert into t_operation (intitule,cout,montant,date_op,debit_IBAN,debit_BIC,credit_IBAN,credit_BIC) 
	values (indications,coutOp,montantOp,CURRENT_DATE,IBANdebiteur,BICdebiteur,IBANcrediteur,BICcrediteur);

	insert into t_virement_unique (select max(id) from t_operation);
end
$$ language 'plpgsql';




create or replace function creer_virement_permanent(IBANdebiteur int, IBANcrediteur int, BICdebiteur t_compte.BIC%type, BICcrediteur t_compte.BIC%type, montantop float, periode t_virement_permanent.periodicite%type, datedebut date) returns void as $$
declare
	coutOp float := 5.0;
	tmpId int;
begin	
	if not (periode='T' or periode='M' or periode='S' or periode='A') then
		raise exception 'periode inexistante. Valeurs possibles: A, S, T, M';
	end if;
	perform * from t_compte where IBAN = IBANdebiteur and BIC = BICdebiteur and actif=true;
	if not found then 
		raise exception 'compte debiteur inexistant';
	end if;

	perform * from t_compte where IBAN = IBANcrediteur and BIC = BICcrediteur and actif=true;
	if not found then 
		raise exception 'compte crediteur inexistant';
	end if;
	update t_compte set solde = solde + coutOp where 'Banque' = BIC and 0 = IBAN;
	insert into t_operation (intitule,cout,montant,date_op,debit_IBAN,debit_BIC,credit_IBAN,credit_BIC) values ('virement mensuel',coutOp,montantOp,datedebut,IBANdebiteur,BICdebiteur,IBANcrediteur,BICcrediteur);
	select max(id) into tmpId from t_operation;
	insert into t_virement_permanent (id, periodicite) values (tmpId,periode);
	update t_compte set solde = solde - coutOp where IBAN = IBANdebiteur and BIC = BICdebiteur;
end
$$ language 'plpgsql';




create or replace function supprimer_virement_permanent(idVirement int) returns void as $$
begin
	perform * from t_virement_permanent where id = idVirement;
	if not found then
		raise exception 'virement inexistant';
	end if;
	delete from t_virement_permanent where id = idVirement;
end
$$ language 'plpgsql';




create or replace function retirer(IBANc int, BICc t_compte.BIC%type, montantOp float) returns void as $$
declare
	maxDebit float;
begin
	perform * from t_compte where IBAN = IBANc and BIC = BICc and actif=true;
	if not found then 
		raise exception 'compte a debiter inexistant';
	end if;

	select (solde + decouvert_autorise + depassement_decouvert) into maxdebit from t_compte where IBAN = IBANc and BIC = BICc;
	if (maxdebit < montantOp) then
		raise exception 'solde insuffisant';
	end if;

	insert into t_operation (intitule,cout,montant,date_op,debit_IBAN,debit_BIC) values ('retrait',0,montantOp,CURRENT_DATE,IBANc,BICc);
	insert into t_retrait (select max(id) from t_operation);
	update t_compte set solde = solde - montantOp where IBAN = IBANc and BIC = BICc;
end
$$ language 'plpgsql';




create or replace function depot(IBANc int, BICc t_compte.BIC%type, montantOp float) returns void as $$
begin
	perform * from t_compte where IBAN = IBANc and BIC = BICc and actif=true;
	if not found then 
		raise exception 'compte a créditer inexistant';
	end if;

	insert into t_operation (intitule,cout,montant,date_op,credit_IBAN,credit_BIC) values ('depot',0,montantOp,CURRENT_DATE,IBANc,BICc);
	insert into t_retrait (select max(id) from t_operation);
	update t_compte set solde = solde + montantOp where IBAN = IBANc and BIC = BICc;
end
$$ language 'plpgsql';



create or replace function fermeture_compte(IBANc int, BICc t_compte.BIC%type) returns void as $$
begin
	perform * from t_compte where IBAN = IBANc and BIC = BICc and actif=true;
	if not found then 
		raise exception 'compte debiteur inexistant';
	end if;
	
	perform * from t_compte where IBAN = IBANc and BIC = BICc and solde=0;
	if not found then 
		raise exception 'le solde doit etre a 0 pour fermer le compte';
	end if;

	update t_compte set actif = false where IBAN = IBANc and BIC = BICc;

end;
$$ language 'plpgsql';



/*fonction Consultation du solde*/
create or replace function consultation_du_solde(_iban int, _bic t_compte.BIC%type, _id_client int) returns float as $$
declare
	_solde float;
begin
	
	perform * from t_compte_vue where proprietaire= _id_client;
	if not found then
		RAISE exception 'client inexistant';
	end if;

	select solde into _solde from t_compte t, t_compte_vue v 
		where t.iban = _iban and t.bic = _bic and t.iban = v.iban and t.bic = v.bic and proprietaire = _id_client;
	if _solde = null then
		RAISE exception 'compte inexistant';
	end if;	
	
return _solde;
end
$$ language plpgsql;



/*1.Ouverture une compte, avec client inexistant*/
CREATE OR REPLACE FUNCTION ouverture_compte_vue(client varchar(10), nom_client varchar(40), adresse_client varchar(40), tel_client varchar(13), prenom_client varchar(40),sexe_client char, iban_compte int, bic_compte t_compte.BIC%type)
RETURNS void AS $$
DECLARE
	id int;
BEGIN	

	INSERT INTO t_client(nom, adresse, tel) VALUES (nom_client, adresse_client, tel_client);

	select max(ID_client) into id from t_client;
		
		
	if client ='personne' then 
		INSERT INTO t_personne(ID_personne, prenom, sexe) VALUES (id, prenom_client, sexe_client);
	else 
		if client = 'entreprise' then 
			INSERT INTO t_entreprise(ID_entr) VALUES (id);
		else 
			if client = 'association' then 
				insert into t_association(ID_ass) values (id);
			end if;
		end if;
	end if;
	
	INSERT INTO t_compte(iban, bic) VALUES (iban_compte, bic_compte);
	insert into t_compte_vue(IBAN, BIC, proprietaire) values(iban_compte, bic_compte, id);
END
$$ LANGUAGE ’plpgsql’;



/*Ouverture une compte, avec client existant*/
CREATE OR REPLACE FUNCTION ouverture_compte(client_id int, iban_compte int, bic_compte varchar(20))
RETURNS void AS $$
BEGIN
	perform * from t_client where id_client = client_id;
	if not found then
		RAISE exception 'client inexistant';
	end if;

	INSERT INTO t_compte(iban, bic) VALUES (iban_compte, bic_compte);

	insert into t_compte_vue(IBAN, BIC, proprietaire) values(iban_compte, bic_comptet, client_id);

END
$$ LANGUAGE ’plpgsql’;



/*créer un mandataire avec client inexistant*/
create or replace function creer_mandataire(nom_mandataire varchar(40), adresse_mandataire varchar(40), tel_mandataire varchar(13), prenom_mandataire varchar(40),sexe_mandataire char, iban_compte int, bic_compte t_compte.bic%type) returns void as $$
declare
	id int;
begin
 	perform * from t_compte where iban = iban_compte and bic = bic_compte;
	if not found then
		RAISE exception 'compte inexistant';
	end if;

	select proprietaire INTO id from t_compte_vue where iban = iban_compte and bic = bic_compte;
	
	INSERT INTO t_client(nom, adresse, tel) VALUES (nom_mandataire, adresse_mandataire, tel_mandataire);

	select max(ID_client) into id from t_client;

	INSERT INTO t_personne(ID_personne, prenom, sexe) VALUES (id, prenom_mandataire, sexe_mandataire);
	
	INSERT INTO t_mandataire(personne_id, compte_iban, compte_bic)
	VALUES (id, iban_compte, bic_compte);
end
$$ LANGUAGE 'plpgsql';



/*CREER un mandataire qui est client*/
create or replace function creer_mandataire(id_mandataire int, iban_compte int, bic_compte t_compte.BIC%type) returns void as $$
declare
	id int;
begin
	perform 'select * from t_compte where iban = iban_compte and bic = bic_compte';
	if not found then
		RAISE EXCEPTION 'compte inexistant';
	end if;

	perform * from t_personne where id_personne = id_mandataire;
	if not found then
		raise exception 'personne inexistante';
	end if;
	
	INSERT INTO t_mandataire(personne_id, compte_iban, compte_bic)
	VALUES (id_mandataire, iban_compte, bic_compte);
end
$$ LANGUAGE 'plpgsql';



/*2.function devenir interdit bancaire*/
create or replace function interdit_bancaire(_client int, _motif varchar(100)) returns void as $$
declare
	x record;
begin
	perform * from t_client where id_client = _client;
	if not found then
		raise exception 'client inexistant';
	end if;

	for x in
		select iban, bic from t_compte_vue where proprietaire = _client
	loop
		for y in 
			select * from t_cheque
		loop
			suppression_moyen_paiement(x.iban, x.bic, y.id);
		end loop;
	end loop;

	insert into FCC.interdit_bancaire(id_compte, motif, date_interdit)
	values (cast (_client as varchar), _motif, current_date);
	
EXCEPTION
	when raise_exception then
		raise_notice '';
end
$$ language plpgsql;



/*2.2 function ne_plus_etre_interdit_bancaire*/
create or replace function ne_plus_etre_interdit_bancaire(_client int) returns void as $$
declare
	x record;
begin
	perform * from t_client where id_client = _client;
	if not found then
		raise exception 'client inexistant';
	end if;

	perform * from FCC.interdit_bancaire where id_client = _client and banque=current_user;
	if not found then
		raise exception 'client non interdit bancaire';
	end if;
	
	update FCC.interdit_bancaire
	set date_regularisation = current_date
	where id_client = cast (_client as varchar) and banque=current_user;
end
$$ language plpgsql;


/*3.function autorise decouvert*/
create or replace function autorise_decouvert(_iban int, _bic varchar(20), autorise float, depassement float) returns void as $$
begin
	perform * from t_compte where iban = _iban and bic = _bic;
	if not found then
		raise exception 'compte inexistant';
	end if;

	update t_compte
	set decouvert_autorise = autorise, taux_decouvert = 0.2, depassement_decouvert = depassement, taux_agios = 0.3
	where iban = _iban and bic = _bic;
end
$$ language plpgsql;



/*4. function interdit decouvert*/
create or replace function interdit_decouvert(_iban int, _bic varchar(20)) returns void as $$
begin
	perform * from t_compte where iban = _iban and bic = _bic;
	if not found then
		raise exception 'compte inexistant';
	end if;

	update t_compte
	set decouvert_autorise = 0, taux_decouvert = 0, depassement_decouvert = 0, taux_agios = 0
	where iban = _iban and bic = _bic;
end
$$ language plpgsql;

