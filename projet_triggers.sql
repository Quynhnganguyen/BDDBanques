
create or replace function payer_frais_moyens_paiement() returns trigger as $$

declare
	compte record;
	_cout float;
begin
	if (old.mois <> new.mois) then 
		for compte in 	
			select * from t_compte where actif = true
		loop
			select sum(prix) into _cout from t_moyen_paiement, t_avantage 
				where id=moyen_paiement_id and compte_iban=compte.iban and compte_bic=compte.bic;
				
			insert into t_operation(intitule,cout,date_op,debit_iban, debit_bic)
			values('frais moyens paiement', _cout,current_date,compte.iban,compte.bic);
			
			update t_compte set solde = solde + _cout where iban=0 and bic='Banque';
			update t_compte set solde = solde - _cout where iban=compte.iban and bic=compte.bic;
		end loop;
	end if;
	return new;
end
$$ language plpgsql;

create trigger payer_frais_moyens_paiement after update on t_date
for each row
execute procedure payer_frais_moyens_paiement();

/*trigger Creer releve de compte*/
create or replace function creer_releve_de_compte() returns trigger as $$
declare
	compte record;
	oper record;
	_montant float;
	_cout float := 0;
begin
	if (old.mois <> new.mois) then 
		delete from t_releve_compte;
		for compte in 	
			select * from t_compte where actif = true
		loop
			for oper in
				select * from t_operation, t_date where mois=(extract month from date_op) and 
				((compte.iban = debit_iban and compte.bic = debit_bic) 
				or (compte.iban = credit_iban and compte.bic = credit_bic))
			loop
				_montant := oper.montant;
				if (compte.iban = oper.debit_iban and compte.bic = oper.debit_bic) then
					_montant := _montant*(-1);
					_cout := oper.cout;
				end if;
				insert into t_releve_compte(compte.iban, compte.bic, oper.date_op, oper.intitule, _montant, _cout);
			end loop;
		end loop;
	end if;
	
return new;
end
$$ language plpgsql;

create trigger creer_releve_de_compte after update on t_date
for each row
execute procedure creer_releve_de_compte();

/*trigger remunerer sur update on table t_date*/
create or replace function remunerer() returns trigger as $$
declare
	x record;
	new_solde float;
	sstot float;
begin
	for x in
		select * from t_compte where solde >= 1000
	loop
		sstot = x.solde -1000;
		new_solde = x.solde + (0.005/365 * sstot);
		
		update t_compte set solde = new_solde where iban= x.iban and bic = x.bic;
	end loop;		
	return new;
end
$$ language plpgsql;

create trigger remunerer after update on t_date
for each row
execute procedure remunerer();

/*trigger payer frais de decouvert */

create or replace function payer_frais_decouvert() returns trigger as $$
declare
	frais float;
	x record;
begin
	for x in
		select * from t_compte where solde<0
	loop
		if ((x.solde + x.decouvert_autorise) >= 0) then frais = (-x.solde)*x.taux_decouvert ;
		else
			frais = x.decouvert_autorise * x.taux_decouvert + (-(x.solde + x.decouvert_autorise))* x.taux_agios;
		end if;		
		
		update t_compte set solde = solde + frais where iban=0 and bic='Banque';
		update t_compte set solde = solde - frais where iban = x.iban and bic = x.bic;
		
		insert into t_operation(intitule,cout,date_op,debit_iban, debit_bic)
			values('decouvert et depassement de decouvert', frais,current_date,x.iban,x.bic);
			
	end loop;	
	return new;
end
$$language plpgsql;

create trigger payer_frais_decouvert after update on t_date
for each row
execute procedure payer_frais_decouvert();



create or replace function virement_mensuel() returns trigger as $$
declare
	listeId record;
begin
	for listeId in 
	 	select * from t_date, t_virement_permanent p, t_operation o 
			where p.id=o.id and extract(day from date_op)=jour 
				and ((periodicite='M') 
					or (periodicite='T' and cast(extract(month from date_op) as int)%3=mois%3) 
					or (periodicite='S' and cast(extract(month from date_op) as int)%6=mois%6) 
					or (periodicite='A' and extract(month from date_op)=mois)) 
				and (cast(extract(year from date_op) as int) < annee 
				or (cast(extract(year from date_op) as int) = annee 
				and cast(extract(month from date_op) as int) <= mois))

	loop
		perform virement_unique_intra(listeId.debit_IBAN, listeId.credit_IBAN, listeId.debit_BIC, listeId.credit_BIC, listeId.montant, 1, 'virement mensuel');
	end loop;
	return new;
EXCEPTION 
	when RAISE_EXCEPTION then
		raise notice 'paiement impossible';
	return new;
end
$$ language 'plpgsql';

create trigger virement_mensuel after update on t_date
for each row
execute procedure virement_mensuel();

